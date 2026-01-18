# MultiStrategyVault – Token Metrics Take-Home Assignment

## Overview

`MultiStrategyVault` is an ERC-4626 compliant vault that accepts deposits of a single underlying asset (e.g., USDC) and routes capital across multiple yield-generating strategies based on configurable target allocations.

The vault aggregates value across strategies, manages withdrawals with lockup-aware liquidity handling, enforces allocation caps to prevent concentration risk, and provides emergency pause functionality for safety.

This project is designed to be minimal and explicit, focusing on correctness and risk management rather than production complexity.

- Users interact **only** with `MultiStrategyVault`
- Strategies act as execution layers
- All economic ownership resides in the vault

---

## Core Features

### 1. ERC-4626 Vault

- Users deposit assets and receive vault shares
- Shares represent proportional ownership of total vault value
- Share price reflects aggregate yield from all strategies

---

### 2. Multi-Strategy Routing

- Capital is allocated using **basis points (bps)**
- Only `MANAGER_ROLE` can configure allocations and rebalance
- `totalAssets()` aggregates:
  - Idle vault balance
  - Assets deployed in each strategy

---

### 3. Withdrawal Queue (Lockup-Aware)

Withdrawals are handled depending on liquidity availability:

- **Instant liquidity strategies**
  - Assets withdrawn immediately

- **Lockup-based strategies**
  - Withdrawal is queued
  - User claims assets later once liquidity becomes available

Flow:

1. User requests withdrawal and burns shares
2. Vault withdraws immediately available liquidity
3. Remaining amount is queued
4. User calls `claimWithdraw()` when assets are unlocked

---

### 4. Allocation Caps & Concentration Risk Prevention

#### What is concentration risk?

Concentration risk occurs when too much capital is allocated to a single strategy.  
If that strategy underperforms or fails, a large portion of user funds is exposed.

#### How this vault prevents it

Allocation caps are enforced at **multiple stages**:

- **Configuration-time**
  - Per-strategy maximum allocation (e.g., 60%)
  - Total allocation must equal 100%

- **Deposit-time**
  - New deposits respect existing exposure and per-strategy caps
  - Prevents gradual drift toward over-allocation

---

### 5. Rebalancing

- Callable only by `MANAGER_ROLE`
- Withdraws excess assets from overweight strategies
- Deposits into underweight strategies
- Lockup strategies are skipped if liquidity is unavailable
- Keeps allocations aligned with targets over time

---

### 6. Emergency Pause

- Admin can pause the vault in emergency scenarios
- When paused:
  - Deposits
  - Mints
  - Withdrawals
  - Rebalances  
    are disabled
- View functions remain accessible

---

## Strategy Model (Important Assumption)

### Vault-Dedicated Strategies

All strategies in this implementation are assumed to be **vault-dedicated**:

- Only `MultiStrategyVault` deposits into strategies
- No external users interact with strategy contracts
- `strategy.totalAssets()` represents assets owned by the vault

> In production systems with shared ERC-4626 strategies, the vault would track strategy shares and convert them to assets using `convertToAssets()`.

---

## Access Control

| Role                 | Permissions                           |
| -------------------- | ------------------------------------- |
| `DEFAULT_ADMIN_ROLE` | Pause / unpause the vault             |
| `MANAGER_ROLE`       | Set allocations, rebalance strategies |

Implemented using OpenZeppelin `AccessControl`.

---

## Safety Considerations

- Allocation caps to prevent concentration risk
- Lockup-aware withdrawal queue
- Emergency pause mechanism
- Custom errors for explicit failure cases
- Minimal trusted assumptions

---

## Summary

This implementation demonstrates:

- ERC-4626 vault mechanics
- Multi-strategy capital routing
- Lockup-aware withdrawal handling
- Allocation cap enforcement
- Emergency safety controls

## ⚙️ Installation & Setup

This project uses **Foundry** for development and testing.

---

### Install Foundry

If you don’t have Foundry installed, run:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Verify installation:

forge --version

### Install Dependencies

The project depends on Solmate and OpenZeppelin Contracts.

```
forge install transmissions11/solmate
forge install OpenZeppelin/openzeppelin-contracts
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
