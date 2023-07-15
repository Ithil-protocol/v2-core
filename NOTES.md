# Implementation Notes

## Resolved Attack Vectors

- The usual ERC4626 vulnerability following small denominators in OpenZeppelin's _mulDiv_ function, is inherited by the
  Vault since it is an ERC4626. The two mitigations suggested by OZ are either adding a slippage parameter (which does
  not solve the vulnerability but the user can protect from it) or ensure the Vault is always filled, even by a small
  amount, of assets.
- In the _Manager_, the calculation of currentExposure adopts OpenZeppelin's _mulDiv_ function, which carries the same
  issues as seen above, a hacker wanting to manipulate the denominator (freeLiquidity - amount) + netLoans thus
  eliminating the enforcing of caps. To mitigate the risk, we introduce both absolute caps and relative caps checks when
  borrowing. Since there is no way to overcome an absolute cap, it is impossible to manipulate the relative caps by
  depositing a massive amount of liquidity in the Vault, while relative caps are still necessary in the case a lot of
  liquidity is withdrawn from the Vault. Absolute caps should be changed only in periods in which the Vault's total
  assets are relatively stable.
- Lack of liquidator reward is a vulnerability, since losing positions would not be liquidated. This has been fixed by
  adding a reward proportional to the liquidation score, from 0 to the position's margin. In this way, the flux margin -
  reward is always positive and liquidating one's own position is always a losing cycle (see Euler's hack).
- Credit services would not withdraw everything in case of a liquidity crunch, leading to an unjustified loss to the
  user. This has been fixed by implementing an "all-or-nothing" principle: if there is not enough liquidity, the
  agreement is not closed, and the user can thus wait for liquidity to flow in again before withdrawing.

- Before the [PR#88](https://github.com/Ithil-protocol/dev/pull/88), we implicitly made an assumption that spreads were
  default for all services, and interest rates were default for all debit services. In reality, we will have (in a
  future PR) one or more InterestRate contracts, and each service will adopt the most suitable one. After this PR, this
  assumption is removed by deleting spreads in the Manager (this makes the Manager smaller). The payoff is computed
  based on the tokens returned by the "close" function, which is totally general in Service.sol. For debit services, the
  payoff is implemented as simply the difference amountsOut - duePayment

## Bad Liquidations

In the context of a debit service, a hacker may syphon out funds from Ithil's vaults with the following procedure:

- Set up it's place in the target protocol in some way (we are agnostic on how).
- Open an agreement on Ithil, thus transferring liquidity to the target protocol.
- Manipulate the quoter via a flashloan which triggers a bad liquidation.
- After liquidation, Ithil has no entitlement anymore on the funds, which would be lost in the target protocol.

The hacker could profit from this (we are still agnostic on how), thus it could repay its flashloan and start again to
drain funds out of Ithil vaults. In order to avoid this, _we exclude non-owner addresses to generate losses on the
vault_. In other words, if a liquidation causes a loss, only the service's owner can perform it. In this way, virtually
any hack of this kind is unfeasible.

_Caveat_: it is now fundamental that the quoter works properly. Enforcement is done on an obtained token basis rather
than on a quoter basis (that is, a liquidation is considered bad if the obtained amount is less than the loan, not
simply if the quoted amount is too low). In the wrong case in which the liquidation score is zero but the obtained
tokens are less than the loan (a clear signal of a bug in the quoter), this would result in an agreement impossible to
close.
