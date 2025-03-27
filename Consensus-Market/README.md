# Policy Prediction Market Smart Contract

## Overview

This Clarity smart contract enables the creation, betting, and resolution of prediction markets focused on policy outcomes. Users can create markets, place bets, and claim winnings based on the actual outcome of policy-related predictions.

## Features

- Create prediction markets with custom descriptions
- Place bets on potential policy outcomes
- Resolve markets with verified results
- Claim winnings for correct predictions
- Refund options for expired markets
- Administrative controls for platform configuration

## Key Functions

### Market Creation
- `create-prediction-market`: Create a new prediction market
  - Specify market description
  - Set market close block
  - Validates market parameters

### Betting
- `place-market-bet`: Place a bet on a specific market outcome
  - Supports multiple bets per user
  - Enforces minimum and maximum bet amounts
  - Transfers bet amount to contract escrow

### Market Resolution
- `resolve-prediction-market`: Resolve a market with its actual outcome
  - Only market creator can resolve
  - Can only resolve after market close block
  - Sets final market outcome

### Winnings
- `claim-market-winnings`: Claim winnings for correct predictions
  - Validates market resolution
  - Transfers winnings to correct predictors

### Additional Utilities
- `refund-expired-market-bet`: Refund bets for unresolved expired markets
- Administrative functions to update platform parameters

## Configuration Parameters

- Minimum bet amount: 10 (configurable)
- Maximum bet amount: 1,000,000 (configurable)
- Market close delay: Between 1 day and 1 year
- Market expiry period: Configurable (default ~2 years)

## Error Handling

The contract includes comprehensive error handling with specific error codes for:
- Invalid market parameters
- Unauthorized access
- Insufficient funds
- Market closure and resolution issues
- Betting constraints

## Security Considerations

- Market creators can only resolve their own markets
- Bet amounts are escrowed during market duration
- Strict validation on market creation and resolution
- Administrative functions restricted to platform admin

## Deployment Requirements

- Stacks blockchain
- Clarity smart contract support
- STX token for betting and transactions

## Usage Example

```clarity
;; Create a market about a policy outcome
(create-prediction-market "Will policy X pass?" block-height-close)

;; Place a bet
(place-market-bet market-id true u100)

;; Resolve market after close block
(resolve-prediction-market market-id true)

;; Claim winnings if prediction was correct
(claim-market-winnings market-id)
```

## Limitations

- Relies on market creator's honesty for resolution
- No external oracle integration
- Limited to boolean (yes/no) outcomes