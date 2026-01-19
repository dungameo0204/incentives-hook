# 🦄 Uniswap V4 Incentive Hook

![License](https://img.shields.io/badge/License-MIT-green.svg)
![Framework](https://img.shields.io/badge/Framework-Foundry-orange.svg)
![Network](https://img.shields.io/badge/Network-Sepolia_Testnet-blue.svg)
![Status](https://img.shields.io/badge/Status-Active-success.svg)

> **A custom Uniswap V4 Hook designed to incentivize liquidity providers with time-weighted ERC20 rewards.**

This project implements a **Liquidity Mining** mechanism directly on-chain using Uniswap V4 Hooks. Liquidity Providers (LPs) earn **SpongeCake (SC)** tokens based on the duration and amount of liquidity they stake in the pool.

---

## 🚀 Live Demo

Interact with the Hook via the frontend interface:
### [🌐 https://frontendincentivehook.vercel.app](https://frontendincentivehook.vercel.app/)

---

## ✨ Key Features

* **⏱ Time-Weighted Rewards:** Rewards are calculated per second. The longer you stake, the more you earn.
* **🎁 Native Reward Token:** Integrated ERC20 token (**SpongeCake** - symbol: `SC`) minted directly to LPs.
* **🔒 On-Chain Verification:** All logic regarding liquidity tracking and reward distribution happens on-chain for maximum transparency.
* **⚡ Auto-Claim:** Rewards are automatically calculated and can be claimed when modifying liquidity.
* **🛡️ Brevis Integration:** Ready for zk-Coprocessor integration for advanced volatility data verification.

---

## 🏗 System Architecture

The system consists of the following components interaction:

1.  **User (LP):** Adds liquidity via the `ModifyLiquidityRouter`.
2.  **Pool Manager:** Handles the core Uniswap V4 logic.
3.  **IncentiveHook:**
    * Intercepts `afterAddLiquidity` / `afterRemoveLiquidity` calls.
    * Tracks `stakedLiquidity` for each position.
    * Mints `SC` tokens as rewards.

---

## 📜 Contract Addresses (Sepolia)

| Contract | Address | Description |
| :--- | :--- | :--- |
| **IncentiveHook** | `0xfbab02f7cf8c284321ed0a0bb4d64ce0eb877fc0` | The main logic & Reward Token (SC) |
| **Pool Reader** | `0xaf60b5ad63380f6998dadfc6175a3baaccf2b682` | Helper for fetching Tick & Price |

---

## 🛠 Getting Started

This project is built with **Foundry**. Ensure you have it installed.

### 1. Installation

```bash
git clone [https://github.com/your-username/incentive-hook.git](https://github.com/your-username/incentive-hook.git)
cd incentive-hook
forge install

2. Build & Test

# Compile contracts
forge build

# Run unit tests
forge test

3. Deploy

Set up your .env file with PRIVATE_KEY and RPC_URL, then run:

forge script script/DeployIncentivesHook.s.sol:DeployIncentivesHook --rpc-url $SEPOLIA_CHAIN --private-key $PRIVATE_KEY --broadcast --legacy --gas-price 2000000000 --slow  --verify