# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer:
The risk is that MINTER_ROLE holds both minting authority and ability to destory other user's token without their permission. Once the VAULT is attacked, a malicious holder could erase a user's balance without returning any collaterals, undermining ownership and trust.Although the current Vault burns only the redeeming caller’s tokens, its permission is broader than necessary.
I would change the SimpleStablecoin to seperate minting authority from burning authority. Minting would keep restricted to the approved contract. Burning tokens from another accounts would be required for the account's explicit permission, with the stablecoin check whether the account owns enough allowance. If only a privileged role is created to burn tokens, the risks may still remain.
I would change Vault so users approve it to burn their sUSD before redemption. It would burn only the redeeming user’s approved amount and return matching collateral to that user. Burning and repayment would occur in one transaction, so a failed collateral transfer would also reverse the burn. Users could limit or revoke approvals, giving them control over how much the Vault may burn.
<br><br><br>

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:
DEFAULT_ADMIN_ROLE would be held by a timelock contract controlled by a governance multisignature wallet. It would manage role assignments and revocations. Multiple independent signers and a delay for ordinary changes would make malicious permission grants harder and give users time to respond.
MINTER_ROLE would be held only by audited Vault contracts that enforce collateral requirements before issuing tokens. Individual administrators and the deployer should not retain unrestricted minting authority. New minters would require governance approval, and issuance should have appropriate limits and monitoring.
PAUSER_ROLE would be held by a separate security multisignature wallet, allowing the incident response team to pause quickly when suspicious activity is detected. Its signers should be sufficiently independent from the governance signers. I would restrict unpausing to governance after investigation, which requires changing the current unpause permission check.

<br><br><br>

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:
I would like to replace the blanket check in the _update with the check that can distinguish ordinary transfer, minting and burning by viewing the sender address and recipient address. Ordinary transfer has both sender and recipient addresses nonzero, while minting has a zero sender address and burning has a zero recipient address. Transfer will be executed after checking the two addresses and making sure it is a burning transfer. The normal ERC20 accounting would still execute after these checks.


<br><br><br>

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:
Closing redemption protects reserves from immediate withdrawals and gives the issuer time to manage a crisis. It can prevent forced asset sales at low prices and reduce the advantage of early redeemers. However, holders lose access to their money, uncertainty increases, and confidence may deteriorate. A freeze also removes the arbitrage mechanism that normally helps maintain a stablecoin’s peg.
Leaving redemption open allows holders to exchange tokens for their promised value. If a token trades at $0.87 but can be redeemed for $1, traders can buy discounted tokens and redeem them for a profit. Their purchases increase demand and help move the price toward $1, strengthening confidence in the redemption promise.

<br><br><br>

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:
One condition is insufficient backing caused by unauthorized minting. Suppose an attacker obtains MINTER_ROLE and creates 1,000,000 sUSD without depositing USDC. Minting increases totalSupply() while totalCollateral() stays unchanged. If supply exceeds collateral, the invariant fails. The attacker can then redeem tokens against available reserves, taking USDC deposited by legitimate users. Burning these tokens does not repair the shortfall because supply and collateral decrease equally. Remaining holders may lose confidence and sell, pushing the price below the peg.
Another condition is an unavailable redemption channel. For example, pausing the stablecoin prevents the burn needed to redeem sUSD. Collateral may still fully cover outstanding supply, so totalCollateral() >= totalSupply() remains true. Nevertheless, holders cannot exchange their tokens for the backing asset. Traders cannot reliably buy discounted sUSD and redeem it at face value, weakening the arbitrage mechanism that normally supports the peg. Uncertainty about access to funds can therefore trigger selling and a market discount.
<br><br><br>

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:
The attacker first obtains MINTER_ROLE through a corrupt permission grant, then directly mints 1,000,000 sUSD without depositing USDC. Their balance and total supply increase, while the Vault’s collateral remains unchanged. They bypass the collateral requirement enforced by the normal deposit process.
The attacker then redeems the newly minted tokens. The Vault burns their sUSD and transfers an equal amount of USDC from reserves deposited by legitimate users. If the Vault initially holds 1,000,000 USDC backing 1,000,000 legitimate sUSD, this redemption empties the reserves and leaves legitimate holders without backing. A request exceeding available collateral would revert, although smaller redemptions could drain the remaining funds.
The attack could have been stopped at the role grant. MINTER_ROLE should belong only to approved Vault contracts that require collateral before minting. Administrative grants should require secure governance approval. Temporary deployer privileges should also be revoked. Burning authorization would not prevent this attack because the attacker is redeeming their own tokens.
<br><br><br>

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:
The backing principle could remain, but totalCollateral() would need to measure verified dollar value rather than simply count Treasury tokens. Securities differ in denomination, maturity, and market price, so their quantity cannot directly be compared with sUSD supply.
Valuation introduces interest-rate risk and dependence on reliable price data. The system would need consistent units, conservative valuation rules, and checks for stale or inaccurate prices.
Ownership and custody also introduce off-chain dependencies. A token may represent securities held by a custodian, so audits and reconciliation must confirm that the underlying assets exist, belong to the reserve structure, and are not pledged elsewhere.
Finally, asset value is different from immediately available cash. Selling Treasuries requires settlement, while users may request prompt redemption. A cash buffer or redemption queue may therefore be necessary.
The revised invariant should compare verified asset value, after other liabilities and adjustments, with outstanding redemption obligations expressed in dollars.
<br><br><br>

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:

I would place the building in a legally established ownership structure, such as a special purpose vehicle (SPV), and issue tokens representing clearly defined rights in that structure. The Vault would hold these tokens as collateral. Legal agreements must connect the tokens to enforceable claims; recording a building on the blockchain does not automatically transfer its title.

The arrangement would require lawyers and the relevant property registration process, a trustee or security agent, independent valuers, auditors, and a property manager. Documents would establish ownership, existing mortgages, creditor priority, and procedures for default, sale, and distribution of proceeds.

Valuation would account for outstanding debt, maintenance costs, taxes, and uncertain sale prices. The system should use conservative borrowing limits and periodically update valuations.

Because a building cannot be sold instantly or in arbitrary fractions, immediate redemption would require separate liquid reserves. Otherwise, users would need a clearly defined redemption queue tied to asset sales.

<br><br><br>

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts |test_Ex4_Mint_RevertsForNonMinter | 
| Transfers revert while paused | test_Ex4_Pause_BlocksTransfers |
| **Redemption** reverts while paused | test_Ex4_Pause_BlocksRedeem|
| An attacker cannot burn someone else's balance |test_Ex4_AttackerCannotBurnOthersBalance|
| ...but the vault holding `MINTER_ROLE` can | test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance| 

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer:
I would test an attacker attempting to redeem more sUSD than they own while the Vault has sufficient collateral. This is attractive because redemption is a public function that transfers reserve assets, so any account can attempt to exploit it.
The test should first have Alice deposit USDC and receive sUSD, ensuring the Vault contains collateral. The attacker would then request an amount within the Vault’s reserves but above their own sUSD balance. The transaction should revert, and the Vault’s collateral, total sUSD supply, and both users’ token balances should remain unchanged.
I chose this scenario because testing against an empty Vault could produce a misleading result: redemption might fail only because collateral is unavailable. Funding the Vault first verifies that the attacker’s insufficient token balance actually prevents withdrawal. It also confirms that a failed redemption cannot partially transfer collateral or alter accounting, protecting legitimate depositors from unauthorized withdrawals.
