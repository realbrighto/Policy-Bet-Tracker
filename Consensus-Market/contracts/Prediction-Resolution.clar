;; Policy Prediction Market Smart Contract

;; Error Constants
(define-constant ERR-INVALID-CLOSE-TIME (err u1))
(define-constant ERR-MARKET-CLOSED (err u2))
(define-constant ERR-MARKET-ALREADY-RESOLVED (err u3))
(define-constant ERR-INVALID-BET (err u4))
(define-constant ERR-MARKET-NOT-FOUND (err u5))
(define-constant ERR-INSUFFICIENT-MARKET-FUNDS (err u6))
(define-constant ERR-MARKET-NOT-CLOSED (err u7))
(define-constant ERR-BET-NOT-FOUND (err u8))
(define-constant ERR-MARKET-NOT-RESOLVED (err u9))
(define-constant ERR-BET-LOST (err u10))
(define-constant ERR-MARKET-EXPIRED (err u11))
(define-constant ERR-MARKET-NOT-EXPIRED (err u12))
(define-constant ERR-UNAUTHORIZED-ACCESS (err u13))
(define-constant ERR-BET-AMOUNT-TOO-LOW (err u14))
(define-constant ERR-BET-AMOUNT-TOO-HIGH (err u15))
(define-constant ERR-INVALID-PARAMETER (err u16))

;; Validation Constants
(define-constant MAX-BLOCK-CLOSE-DELAY u52560)    ;; ~1 year in blocks
(define-constant MIN-BLOCK-CLOSE-DELAY u144)      ;; ~1 day in blocks
(define-constant MAX-MARKET-EXPIRY-DELAY u105120) ;; ~2 years in blocks
(define-constant MIN-DESCRIPTION-LENGTH u10)      ;; Minimum market description length
(define-constant MAX-MARKET-ID u10000)            ;; Maximum allowed market ID

;; Configuration Variables
(define-data-var platform-name (string-ascii 50) "Policy Prediction Market")
(define-data-var next-available-market-id uint u1)
(define-data-var platform-admin principal tx-sender)

;; Market Configuration Settings
(define-data-var market-expiry-period uint u10000)
(define-data-var minimum-bet-amount uint u10)
(define-data-var maximum-bet-amount uint u1000000)

;; Data Structures
(define-map prediction-markets
  { market-identifier: uint }
  {
    market-description: (string-ascii 256),
    market-outcome: (optional bool),
    market-close-block: uint,
    market-expiry-block: uint,
    market-creator: principal
  }
)

(define-map market-bets
  { market-identifier: uint, bettor: principal }
  { 
    bet-amount: uint, 
    predicted-outcome: bool 
  }
)

;; Validation Helpers
(define-private (is-valid-market-identifier (market-id uint))
  (and 
    (< market-id (var-get next-available-market-id))
    (<= market-id MAX-MARKET-ID)
  )
)

(define-private (is-market-past-expiry (market-id uint))
  (let ((market (unwrap! (map-get? prediction-markets { market-identifier: market-id }) false)))
    (>= block-height (get market-expiry-block market))
  )
)

(define-private (validate-description-length (description (string-ascii 256)))
  (and 
    (>= (len description) MIN-DESCRIPTION-LENGTH)
    (<= (len description) u256)
  )
)

(define-private (validate-market-close-time (close-block uint))
  (let 
    ((block-delay (- close-block block-height)))
    (and
      (>= block-delay MIN-BLOCK-CLOSE-DELAY)
      (<= block-delay MAX-BLOCK-CLOSE-DELAY)
    )
  )
)

(define-private (validate-market-expiry-time (close-block uint) (expiry-block uint))
  (let
    ((expiry-delay (- expiry-block close-block)))
    (and
      (> expiry-block close-block)
      (<= expiry-delay MAX-MARKET-EXPIRY-DELAY)
    )
  )
)

(define-private (validate-bet-amount (amount uint))
  (and
    (>= amount (var-get minimum-bet-amount))
    (<= amount (var-get maximum-bet-amount))
  )
)

;; Market Creation Function
(define-public (create-prediction-market 
  (market-description (string-ascii 256)) 
  (market-close-block uint)
)
  (let
    (
      (market-id (var-get next-available-market-id))
      (calculated-expiry-block (+ market-close-block (var-get market-expiry-period)))
    )
    ;; Comprehensive Market Validation
    (asserts! (validate-description-length market-description) ERR-INVALID-PARAMETER)
    (asserts! (validate-market-close-time market-close-block) ERR-INVALID-CLOSE-TIME)
    (asserts! (validate-market-expiry-time market-close-block calculated-expiry-block) ERR-INVALID-PARAMETER)
    (asserts! (< market-id MAX-MARKET-ID) ERR-INVALID-PARAMETER)
    
    (map-set prediction-markets
      { market-identifier: market-id }
      {
        market-description: market-description,
        market-outcome: none,
        market-close-block: market-close-block,
        market-expiry-block: calculated-expiry-block,
        market-creator: tx-sender
      }
    )
    (var-set next-available-market-id (+ market-id u1))
    (ok market-id)
  )
)

;; Betting Function with Enhanced Validation
(define-public (place-market-bet 
  (market-id uint) 
  (predicted-outcome bool) 
  (bet-amount uint)
)
  (begin
    (asserts! (is-valid-market-identifier market-id) ERR-MARKET-NOT-FOUND)
    (asserts! (validate-bet-amount bet-amount) ERR-INVALID-BET)
    
    (let
      (
        (existing-bet (default-to 
          { bet-amount: u0, predicted-outcome: false } 
          (map-get? market-bets { market-identifier: market-id, bettor: tx-sender })
        ))
        (target-market (unwrap! 
          (map-get? prediction-markets { market-identifier: market-id }) 
          ERR-MARKET-NOT-FOUND
        ))
        (total-bet-amount (+ bet-amount (get bet-amount existing-bet)))
      )
      (asserts! (<= total-bet-amount (var-get maximum-bet-amount)) ERR-BET-AMOUNT-TOO-HIGH)
      (asserts! (< block-height (get market-close-block target-market)) ERR-MARKET-CLOSED)
      (asserts! (is-none (get market-outcome target-market)) ERR-MARKET-ALREADY-RESOLVED)
      (asserts! (>= (stx-get-balance tx-sender) bet-amount) ERR-INSUFFICIENT-MARKET-FUNDS)
      
      (map-set market-bets
        { market-identifier: market-id, bettor: tx-sender }
        { 
          bet-amount: total-bet-amount, 
          predicted-outcome: predicted-outcome 
        }
      )
      (stx-transfer? bet-amount tx-sender (as-contract tx-sender))
    )
  )
)

;; Resolve Market Function
(define-public (resolve-prediction-market 
  (market-id uint) 
  (market-outcome bool)
)
  (begin
    (asserts! (is-valid-market-identifier market-id) ERR-MARKET-NOT-FOUND)
    (let
      (
        (market (unwrap! 
          (map-get? prediction-markets { market-identifier: market-id }) 
          ERR-MARKET-NOT-FOUND
        ))
      )
      ;; Validate market resolution conditions
      (asserts! (is-eq tx-sender (get market-creator market)) ERR-UNAUTHORIZED-ACCESS)
      (asserts! (>= block-height (get market-close-block market)) ERR-MARKET-NOT-CLOSED)
      (asserts! (is-none (get market-outcome market)) ERR-MARKET-ALREADY-RESOLVED)
      
      ;; Update market with resolved outcome
      (map-set prediction-markets
        { market-identifier: market-id }
        (merge market { market-outcome: (some market-outcome) })
      )
      (ok true)
    )
  )
)

;; Claim Winnings Function
(define-public (claim-market-winnings (market-id uint))
  (begin
    (asserts! (is-valid-market-identifier market-id) ERR-MARKET-NOT-FOUND)
    (let
      (
        (market (unwrap! 
          (map-get? prediction-markets { market-identifier: market-id }) 
          ERR-MARKET-NOT-FOUND
        ))
        (user-bet (unwrap! 
          (map-get? market-bets { market-identifier: market-id, bettor: tx-sender }) 
          ERR-BET-NOT-FOUND
        ))
      )
      ;; Validate market resolution and bet conditions
      (asserts! (is-some (get market-outcome market)) ERR-MARKET-NOT-RESOLVED)
      (asserts! 
        (is-eq (get predicted-outcome user-bet) 
               (unwrap-panic (get market-outcome market))) 
        ERR-BET-LOST
      )
      
      ;; Transfer winnings
      (as-contract 
        (stx-transfer? 
          (get bet-amount user-bet) 
          tx-sender 
          tx-sender
        )
      )
    )
  )
)

;; Configuration Update Functions
(define-public (update-market-expiry-period (new-expiry-period uint))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-admin)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (and 
      (>= new-expiry-period u1000)   ;; Minimum ~1 day
      (<= new-expiry-period u52560)  ;; Maximum ~1 year
    ) ERR-INVALID-PARAMETER)
    (ok (var-set market-expiry-period new-expiry-period))
  )
)

(define-public (update-minimum-bet-amount (new-minimum-amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-admin)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (and 
      (>= new-minimum-amount u1)
      (< new-minimum-amount (var-get maximum-bet-amount))
      (<= new-minimum-amount u1000000)
    ) ERR-INVALID-PARAMETER)
    (ok (var-set minimum-bet-amount new-minimum-amount))
  )
)

(define-public (update-maximum-bet-amount (new-maximum-amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-admin)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (and 
      (> new-maximum-amount (var-get minimum-bet-amount))
      (<= new-maximum-amount u1000000000000)
      (>= new-maximum-amount u1000)
    ) ERR-INVALID-PARAMETER)
    (ok (var-set maximum-bet-amount new-maximum-amount))
  )
)

;; Admin Management Functions
(define-read-only (get-platform-admin)
  (ok (var-get platform-admin))
)

(define-public (transfer-platform-ownership (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get platform-admin)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (is-eq new-admin (var-get platform-admin))) ERR-INVALID-PARAMETER)
    (ok (var-set platform-admin new-admin))
  )
)

;; Refund Expired Market Bets Function
(define-public (refund-expired-market-bet (market-id uint))
  (begin
    (asserts! (is-valid-market-identifier market-id) ERR-MARKET-NOT-FOUND)
    (let
      (
        (market (unwrap! 
          (map-get? prediction-markets { market-identifier: market-id }) 
          ERR-MARKET-NOT-FOUND
        ))
        (user-bet (unwrap! 
          (map-get? market-bets { market-identifier: market-id, bettor: tx-sender }) 
          ERR-BET-NOT-FOUND
        ))
      )
      ;; Validate market expiration and unresolved status
      (asserts! (is-market-past-expiry market-id) ERR-MARKET-NOT-EXPIRED)
      (asserts! (is-none (get market-outcome market)) ERR-MARKET-ALREADY-RESOLVED)
      
      ;; Transfer bet amount back to user
      (as-contract 
        (stx-transfer? 
          (get bet-amount user-bet) 
          tx-sender 
          tx-sender
        )
      )
    )
  )
)