# LemonJet

LemonJet is a single-token multiplier game backed by an ERC4626 vault. Players bet the vault asset token, liquidity providers hold vault shares, and Chainlink VRF resolves each game.

The game is designed around a 1% gross house edge before native VRF payment cost and before vault-share rewards minted to the reserve fund or referrers.

## Core Parameters

Current game constants:

```text
RANDOM_RANGE = 100_000_000
BASIS_POINT_SCALE = 10_000
HOUSE_EDGE_BPS = 100
HALF_KELLY_BPS = 50
CALLBACK_GAS_LIMIT = 100_000
REQUEST_CONFIRMATIONS = 0
NUM_WORDS = 1
```

Gameplay bounds:

```text
minimum bet = 1000 token units
minimum multiplier = 1.01x
maximum multiplier = 5000x
coef = multiplier * 100
```

## Game Math

Definitions:

```text
b = bet
c = coef
m = c / 100
h = HOUSE_EDGE_BPS / BASIS_POINT_SCALE = 1%
R = RANDOM_RANGE
```

Payout and pending profit exposure:

```text
payout = floor(b * c / 100)
potentialWinnings = payout - b
```

The win threshold is computed with integer floor rounding:

```text
threshold = floor(R * (10_000 - 100) * 100 / (10_000 * c))
```

Chainlink VRF returns one random word. The contract maps it into the inclusive range `1..R`:

```text
roll = (randomWord % R) + 1
win if roll <= threshold
```

Exact on-chain win probability:

```text
p_exact = threshold / R
```

Approximate continuous win probability:

```text
p ~= (1 - h) / m
```

Player token EV before native VRF cost:

```text
EV_player = p_exact * payout - b
EV_player ~= -1% * b
```

Vault token EV before reward-share dilution:

```text
EV_vault_gross = -EV_player
EV_vault_gross ~= +1% * b
```

## LP Economics

Liquidity providers deposit the game token into the ERC4626 vault and receive vault shares.

Gross expected vault gain from gameplay:

```text
EV_vault_gross ~= +1.0% * bet
```

The protocol also mints vault shares during play. These rewards are not paid by transferring underlying tokens out of the vault; they are minted as shares using the current ERC4626 conversion rate.

Reserve fund reward on every play:

```text
reserveMintValue = bet * 20 / 10_000
reserveMintValue = 0.2% * bet
```

Referral reward when a referrer exists:

```text
referralMintValue = bet * 30 / 10_000
referralMintValue = 0.3% * bet
```

Approximate LP economics after reward-share dilution:

```text
no referrer:   +1.0% - 0.2%        = +0.8% of bet
with referrer: +1.0% - 0.2% - 0.3% = +0.5% of bet
```

This is an expected-value model. Realized LP returns depend on variance, active pending games, vault size, exit timing, and the distribution of chosen multipliers.

## Risk Cap

Each game records two pending liability values:

```text
payout_i = full token amount paid if game i wins
potentialWinnings_i = payout_i - bet_i
```

Aggregate pending accounting:

```text
totalPendingPayouts = sum(payout_i)
totalPendingWinnings = sum(potentialWinnings_i)
```

The settled bankroll removes locked pending principal and pending profit from the live token balance:

```text
settledBankroll = totalAssets + totalPendingWinnings - totalPendingPayouts
```

Because:

```text
totalPendingPayouts = sum(bet_i + potentialWinnings_i)
settledBankroll = totalAssets - sum(bet_i)
```

The aggregate risk cap is half-Kelly-sized relative to settled bankroll:

```text
maxAggregatePendingWinnings = settledBankroll * 50 / 10_000
maxWinAmount = maxAggregatePendingWinnings - totalPendingWinnings
```

If current pending winnings already consume the cap:

```text
maxWinAmount = 0
```

A new game is accepted only when:

```text
potentialWinnings <= maxWinAmount
```

This caps aggregate pending profit exposure across all players, not only per-player exposure.

## Withdrawals And Exit Fees

Initial game liquidity must be supplied through the LemonJet ERC4626 `deposit` or `mint` flow. Do not direct-transfer the game token to the LemonJet contract for bankroll seeding; direct transfers are unsupported accounting donations.

Pending payouts are excluded from withdrawable assets:

```text
withdrawableAssets = max(totalAssets - totalPendingPayouts, 0)
```

`maxWithdraw()` and `maxRedeem()` both respect this pending payout reserve.

The ERC4626 exit fee is:

```text
exitFeeBasisPoints = 200 = 2%
```

On redeem, the requested share amount is fixed and the returned asset amount is reduced:

```text
rawAssets = convertToAssets(shares)
fee = rawAssets * 200 / (10_000 + 200)
assetsOut = rawAssets - fee
```

On withdraw, the requested output assets are fixed and the required shares include the fee:

```text
fee = assets * 200 / 10_000
sharesBurned = convertToShares(assets + fee)
```

On exits, the reserve fund also receives newly minted shares:

```text
sharesWithoutExitFee = shares * 10_000 / (10_000 + 200)
reserveShares = sharesWithoutExitFee * 10 / 10_000
```

## VRF And Native Payments

Each play pays Chainlink VRF direct funding in the chain native token.

The request price is calculated from the wrapper:

```text
requestPrice = wrapper.calculateRequestPriceNative(100_000, 1)
```

The player must send at least that amount:

```text
msg.value >= requestPrice
```

The contract sends exactly `requestPrice` to the VRF wrapper. Excess native payment is refunded when possible. If the refund call fails, the excess remains in the contract and can be swept to `reserveFund` by `claimNativeBalance()`.

VRF response settings:

```text
callbackGasLimit = 100_000
requestConfirmations = 0
numWords = 1
```
