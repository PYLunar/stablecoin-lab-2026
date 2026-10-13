// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title Ex2 + Ex4 — hands-on tasks: turn red into green
/// @notice Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/Stablecoin.t.sol — it contains the answers. Write yours
///         first, and only look once you are stuck.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
        uint256 amount = uint256(raw) % 1_000_000e6;
        vm.assume(amount>0);

        usdc.faucet(alice,amount);
        uint256 supplyBefore = stable.totalSupply();

        vm.startPrank(alice);
        usdc.approve(address(vault),amount);
        vault.deposit(amount);
        vm.stopPrank();

        assertEq(stable.totalSupply()-supplyBefore,amount);
        assertEq(stable.balanceOf(alice),amount);

        assertEq(stable.totalSupply(),vault.totalCollateral());
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is one billion USDC.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {
        //make amount = 1000e18 instead of 1000e6
        uint256 amount = 1000e18;
        usdc.faucet(alice,amount);
        //deposit
        vm.startPrank(alice);
        usdc.approve(address(vault),amount);
        vault.deposit(amount);
        vm.stopPrank();
        // transfer finished, check the number of balance and supply
        assertEq(stable.balanceOf(alice), amount);
        assertEq(stable.totalSupply(), amount);
        assertEq(vault.totalCollateral(), stable.totalSupply());
        // Turn to the actual token_number
        uint256 actual = stable.balanceOf(alice)/(10**uint256(stable.decimals()));
        assertEq(actual,1e15);
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    // a self-defined function
    function _ex4DepositForAlice(uint256 amount) internal {
        usdc.faucet(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }
    
    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {
        bytes32 role = stable.MINTER_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                role
            )
        );
        vm.prank(attacker);
        stable.mint(attacker, 1000e6);

        assertEq(stable.balanceOf(attacker), 0);
        assertEq(stable.totalSupply(), 0);
    }

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {
        _ex4DepositForAlice(1000e6);
        stable.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        stable.transfer(attacker, 100e6);

        assertEq(stable.balanceOf(alice), 1000e6);
        assertEq(stable.balanceOf(attacker), 0);
    }

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {
        _ex4DepositForAlice(1000e6);
        stable.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        vault.redeem(100e6);

        // 失败后，稳定币和抵押物都保持原状
        assertEq(stable.balanceOf(alice), 1000e6);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(vault.totalCollateral(), 1000e6);
    }

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        _ex4DepositForAlice(1000e6);
        bytes32 role = stable.MINTER_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                role
            )
        );
        vm.prank(attacker);
        stable.burn(alice, 100e6);

        assertEq(stable.balanceOf(alice), 1000e6);
        assertEq(stable.totalSupply(), 1000e6);
    }

    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.
    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
        _ex4DepositForAlice(1000e6);

        assertTrue(stable.hasRole(stable.MINTER_ROLE(), address(vault)));
        assertEq(stable.allowance(alice, address(vault)), 0);

        // 模拟以 Vault 的身份调用稳定币
        vm.prank(address(vault));
        stable.burn(alice, 100e6);

        assertEq(stable.balanceOf(alice), 900e6);
        assertEq(stable.totalSupply(), 900e6);

        // 这里只销毁了稳定币，没有返还抵押物
        assertEq(vault.totalCollateral(), 1000e6);
    }
}

// export VAULT=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
// export SUSD=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
// export USDC=0x5FbDB2315678afecb367f032d93F642f64180aa3