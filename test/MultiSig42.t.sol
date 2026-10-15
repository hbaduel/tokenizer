// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {MultiSig42} from "../code/MultiSig42.sol";
import {Hbaduel42Token} from "../code/Hbaduel42Token.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";

contract MultiSig42Test is Test {
    MultiSig42 public multiSig;
    address public owner1;
    address public owner2;
    address public owner3;
    address public externalUser;
    uint256 public nbConfirmationsRequired;
    Hbaduel42Token public token;
    uint256 public mintAmount;

    function setUp() public {
        owner1 = makeAddr("Owner 1");
        owner2 = makeAddr("Owner 2");
        owner3 = makeAddr("Owner 3");
        externalUser = makeAddr("External User");
        nbConfirmationsRequired = 2;

        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;

        multiSig = new MultiSig42(owners, nbConfirmationsRequired);

        address multiSigAddress = address(multiSig);
        token = new Hbaduel42Token(multiSigAddress, multiSigAddress);
        mintAmount = token.MAX_SUPPLY() - token.INITIAL_SUPPLY();
    }

    function getData() private view returns (bytes memory) {
        return abi.encodeCall(Hbaduel42Token.mint, (address(multiSig), mintAmount));
    }

    function test_invalidDeployment() public {
        address[] memory emptyOwners = new address[](0);
        vm.expectRevert(MultiSig42.OwnersEmpty.selector);
        new MultiSig42(emptyOwners, 1);

        address[] memory ownersWithZeroAddress = new address[](2);
        ownersWithZeroAddress[0] = owner1;
        ownersWithZeroAddress[1] = address(0);
        vm.expectRevert(MultiSig42.OwnersArrayContainsZeroAddress.selector);
        new MultiSig42(ownersWithZeroAddress, 1);

        address[] memory ownersWithDuplicate = new address[](2);
        ownersWithDuplicate[0] = owner1;
        ownersWithDuplicate[1] = owner1;
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.OwnersArrayContainsDuplicateAddress.selector, owner1));
        new MultiSig42(ownersWithDuplicate, 1);

        vm.expectRevert(abi.encodeWithSelector(MultiSig42.InvalidNumberOfConfirmations.selector, 1, 3, 4));
        new MultiSig42(new address[](3), 4);
    }

    function test_deployment() public view {
        assertEq(multiSig.nbConfirmationsRequired(), nbConfirmationsRequired);
        assertEq(multiSig.owners(0), owner1);
        assertEq(multiSig.owners(1), owner2);
        assertEq(multiSig.owners(2), owner3);
    }

    function test_revertWhenMultiSigOwnerMintWithoutTransaction() public {
        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner1));
        token.mint(externalUser, mintAmount);
    }

    function test_submitTransaction() public returns (uint256) {
        address tokenAddress = address(token);
        bytes memory _data = getData();
        uint256 initialTransactionCount = multiSig.getTransactionCount();
        vm.prank(owner1);
        vm.expectEmit(address(multiSig));
        emit MultiSig42.TransactionSubmitted(initialTransactionCount, owner1, tokenAddress, _data);
        uint256 transactionId = multiSig.submitTransaction(tokenAddress, _data);

        (address to, bytes memory data, bool executed, uint256 nbConfirmations) = multiSig.transactions(transactionId);
        assertEq(to, tokenAddress);
        assertEq(data, _data);
        assertFalse(executed);
        assertEq(nbConfirmations, 0);
        return transactionId;
    }

    function test_revertWhenInvalidSubmitter() public {
        bytes memory _data = getData();
        vm.prank(externalUser);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.NotAnOwner.selector, externalUser));
        multiSig.submitTransaction(address(0x123), _data);
    }

    function test_revertWhenSubmitToInvalidAddress() public {
        bytes memory _data = getData();
        vm.prank(owner1);
        vm.expectRevert(MultiSig42.TransactionToZeroAddress.selector);
        multiSig.submitTransaction(address(0), _data);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.TransactionToNonContractAddress.selector, address(0x123)));
        multiSig.submitTransaction(address(0x123), _data);
    }

    function test_confirmTransaction() public {
        uint256 transactionId = test_submitTransaction();

        vm.prank(owner1);
        vm.expectEmit(address(multiSig));
        emit MultiSig42.TransactionConfirmed(transactionId, owner1);
        multiSig.confirmTransaction(transactionId);

        (,,, uint256 nbConfirmations) = multiSig.transactions(transactionId);
        assertEq(nbConfirmations, 1);
        assertTrue(multiSig.isConfirmed(transactionId, owner1));
    }

    function test_revertWhenTransactionDoesNotExist() public {
        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.TransactionDoesNotExist.selector, 0));
        multiSig.confirmTransaction(0);
    }

    function test_revertWhenInvalidConfirmer() public {
        uint256 transactionId = test_submitTransaction();

        vm.prank(externalUser);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.NotAnOwner.selector, externalUser));
        multiSig.confirmTransaction(transactionId);
    }

    function test_revertWhenAlreadyConfirmed() public {
        uint256 transactionId = test_submitTransaction();

        vm.prank(owner1);
        multiSig.confirmTransaction(transactionId);

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.TransactionAlreadyConfirmed.selector, transactionId, owner1));
        multiSig.confirmTransaction(transactionId);
    }

    function test_executeTransaction() public returns (uint256) {
        uint256 transactionId = test_submitTransaction();

        vm.prank(owner1);
        multiSig.confirmTransaction(transactionId);

        vm.prank(owner2);
        multiSig.confirmTransaction(transactionId);

        vm.prank(owner1);
        vm.expectEmit(address(multiSig));
        emit MultiSig42.TransactionExecuted(transactionId, owner1);
        multiSig.executeTransaction(transactionId);

        (,, bool executed,) = multiSig.transactions(transactionId);
        assertTrue(executed);
        assertEq(token.totalSupply(), token.MAX_SUPPLY());
        assertEq(token.balanceOf(address(multiSig)), token.MAX_SUPPLY());
        return transactionId;
    }

    function test_revertConfirmWhenAlreadyExecuted() public {
        uint256 transactionId = test_executeTransaction();

        vm.prank(owner3);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.TransactionAlreadyExecuted.selector, transactionId));
        multiSig.confirmTransaction(transactionId);
    }

    function test_revokeTransaction() public {
        uint256 transactionId = test_submitTransaction();

        vm.prank(owner1);
        multiSig.confirmTransaction(transactionId);

        vm.prank(owner1);
        vm.expectEmit(address(multiSig));
        emit MultiSig42.TransactionRevoked(transactionId, owner1);
        multiSig.revokeConfirmation(transactionId);

        (,,, uint256 nbConfirmations) = multiSig.transactions(transactionId);
        assertEq(nbConfirmations, 0);
        assertFalse(multiSig.isConfirmed(transactionId, owner1));
    }

    function test_revertWhenRevokeWithoutConfirmation() public {
        uint256 transactionId = test_submitTransaction();

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.TransactionNotConfirmed.selector, transactionId, owner1));
        multiSig.revokeConfirmation(transactionId);
    }

    function test_revertWhenRevokeAfterExecution() public {
        uint256 transactionId = test_executeTransaction();

        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.TransactionAlreadyExecuted.selector, transactionId));
        multiSig.revokeConfirmation(transactionId);
    }

    function test_revertWhenInvalidRevoker() public {
        uint256 transactionId = test_submitTransaction();

        vm.prank(externalUser);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.NotAnOwner.selector, externalUser));
        multiSig.revokeConfirmation(transactionId);
    }

    function test_revertExecuteWhenAlreadyExecuted() public {
        uint256 transactionId = test_executeTransaction();

        vm.prank(owner2);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.TransactionAlreadyExecuted.selector, transactionId));
        multiSig.executeTransaction(transactionId);
    }

    function test_revertExecuteWhenNotEnoughConfirmations() public {
        uint256 transactionId = test_submitTransaction();

        vm.prank(owner1);
        multiSig.confirmTransaction(transactionId);

        vm.prank(owner1);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiSig42.NotEnoughConfirmations.selector, transactionId, 1, nbConfirmationsRequired
            )
        );
        multiSig.executeTransaction(transactionId);
    }

    function test_revertWhenInvalidExecutor() public {
        uint256 transactionId = test_submitTransaction();

        vm.prank(owner1);
        multiSig.confirmTransaction(transactionId);

        vm.prank(owner2);
        multiSig.confirmTransaction(transactionId);

        vm.prank(externalUser);
        vm.expectRevert(abi.encodeWithSelector(MultiSig42.NotAnOwner.selector, externalUser));
        multiSig.executeTransaction(transactionId);
    }

    function test_canRetryWhenExecutionFailed() public {
        test_executeTransaction();

        // MAX_SUPPLY reached, so the next mint will fail
        uint256 transactionId = test_submitTransaction();

        vm.prank(owner1);
        multiSig.confirmTransaction(transactionId);
        vm.prank(owner2);
        multiSig.confirmTransaction(transactionId);

        uint256 maxSupply = token.MAX_SUPPLY();
        vm.prank(owner1);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiSig42.TransactionExecutionFailed.selector,
                transactionId,
                abi.encodeWithSelector(Hbaduel42Token.ExceedsMaximumSupply.selector, mintAmount, maxSupply)
            )
        );
        multiSig.executeTransaction(transactionId);

        (,, bool executed,) = multiSig.transactions(transactionId);
        assertFalse(executed);
    }

    function test_executeTransferTransaction() public returns (uint256) {
        address tokenAddress = address(token);
        bytes memory _data = abi.encodeCall(token.transfer, (externalUser, 100));
        vm.prank(owner1);
        uint256 transactionId = multiSig.submitTransaction(tokenAddress, _data);

        vm.prank(owner1);
        multiSig.confirmTransaction(transactionId);

        vm.prank(owner2);
        multiSig.confirmTransaction(transactionId);

        vm.prank(owner1);
        multiSig.executeTransaction(transactionId);

        assertEq(token.balanceOf(address(multiSig)), token.INITIAL_SUPPLY() - 100);
        assertEq(token.balanceOf(externalUser), 100);
        return transactionId;
    }
}
