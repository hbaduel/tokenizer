// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Test} from "forge-std/Test.sol";
import {Hbaduel42Token} from "../code/Hbaduel42Token.sol";

contract Hbaduel42TokenTest is Test {
    Hbaduel42Token public token;
    address public owner;
    address public receiver;
    uint256 public unit;
    uint256 public initialSupply;
    uint256 public maxSupply;

    uint256 private constant TEST_AMOUNT = 1 * 10 ** 18;
    address private newOwner = makeAddr("New Owner");

    function setUp() public {
        owner = makeAddr("John Doe");
        receiver = makeAddr("Jean Dupont");
        token = new Hbaduel42Token(owner, receiver);
        unit = token.UNIT();
        initialSupply = token.INITIAL_SUPPLY();
        maxSupply = token.MAX_SUPPLY();
    }

    function test_deployment() public view {
        assertEq(token.name(), "Hbaduel42Token");
        assertEq(token.symbol(), "HFT");
        assertEq(token.totalSupply(), initialSupply);
        assertEq(token.balanceOf(receiver), initialSupply);
        assertEq(owner, token.owner());
        assertEq(unit, 10 ** token.decimals());
        assertEq(unit, TEST_AMOUNT);
    }

    function test_validMint() public {
        uint256 toMax = (maxSupply - initialSupply);
        vm.prank(owner);
        token.mint(receiver, toMax);
        assertEq(token.totalSupply(), initialSupply + toMax);
        assertEq(token.balanceOf(receiver), initialSupply + toMax);
    }

    function test_revertWhenInvalidMinter() public {
        vm.prank(receiver);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, receiver));
        token.mint(receiver, TEST_AMOUNT);
    }

    function test_revertWhenMintExceedsMaxSupply() public {
        test_validMint();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Hbaduel42Token.ExceedsMaximumSupply.selector, TEST_AMOUNT, maxSupply));
        token.mint(receiver, TEST_AMOUNT);
    }

    function test_revertWhenMintToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.mint(address(0), TEST_AMOUNT);
    }

    function test_transfer() public {
        vm.prank(receiver);
        token.transfer(owner, TEST_AMOUNT);
        assertEq(token.balanceOf(receiver), initialSupply - TEST_AMOUNT);
        assertEq(token.balanceOf(owner), TEST_AMOUNT);
    }

    function test_revertWhenTransferExceedBalance() public {
        uint256 receiverBalance = token.balanceOf(receiver);
        uint256 transferAmount = receiverBalance + TEST_AMOUNT;
        vm.prank(receiver);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, receiver, receiverBalance, transferAmount
            )
        );
        token.transfer(owner, transferAmount);
    }

    function test_approve() public {
        vm.prank(receiver);
        token.approve(owner, TEST_AMOUNT);
        assertEq(token.allowance(receiver, owner), TEST_AMOUNT);
    }

    function test_transferFromWithApproval() public {
        test_approve();

        vm.prank(owner);
        token.transferFrom(receiver, owner, TEST_AMOUNT);
        assertEq(token.balanceOf(receiver), initialSupply - TEST_AMOUNT);
        assertEq(token.balanceOf(owner), TEST_AMOUNT);
    }

    function test_revertWhenTransferFromExceedAllowance() public {
        test_approve();

        uint256 allowance = token.allowance(receiver, owner);
        uint256 transferAmount = allowance + TEST_AMOUNT;

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, owner, allowance, transferAmount)
        );
        token.transferFrom(receiver, owner, transferAmount);
    }

    function test_transferOwnership() public {
        vm.prank(owner);
        token.transferOwnership(newOwner);
        assertEq(token.owner(), newOwner);
    }

    function test_mintAfterOwnershipTransfer() public {
        test_transferOwnership();

        uint256 toMax = (maxSupply - initialSupply);
        vm.prank(newOwner);
        token.mint(receiver, toMax);
        assertEq(token.totalSupply(), initialSupply + toMax);
        assertEq(token.balanceOf(receiver), initialSupply + toMax);
    }

    function test_revertWhenMintAfterOwnershipTransferByPreviousOwner() public {
        test_transferOwnership();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        token.mint(receiver, TEST_AMOUNT);
    }

    function test_revertWhenTransferOwnerFromNonOwner() public {
        vm.prank(receiver);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, receiver));
        token.transferOwnership(newOwner);
    }
}
