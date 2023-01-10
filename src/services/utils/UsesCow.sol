// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ICoWSwapSettlement } from "../../interfaces/external/ICowSwapSettlement.sol";
import { ICoWSwapOnchainOrders } from "../../interfaces/external/ICoWSwapOnchainOrders.sol";
import { GPv2Order } from "../../libraries/GPv2Order.sol";
import { CoWSwapEip712 } from "../../libraries/CoWSwapEip712.sol";

contract UsesCow is Ownable, IERC1271, ICoWSwapOnchainOrders {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    struct OnchainData {
        /// @dev The address of the user whom the order belongs to.
        address owner;
        /// @dev The latest timestamp in seconds when the order can be settled.
        uint32 validTo;
    }

    ICoWSwapSettlement public immutable cowSwapSettlement;
    bytes32 internal immutable cowSwapDomainSeparator;

    /// @dev Each ETH flow order as described in [`EthFlowOrder.Data`] can be converted to a CoW Swap order. Distinct
    /// CoW Swap orders have non-colliding order hashes. This mapping associates some extra data to a specific CoW Swap
    /// order. This data is stored onchain and is used to verify the ownership and validity of an ETH flow order.
    /// An ETH flow order can be settled onchain only if converting it to a CoW Swap order and hashing yields valid
    /// onchain data.
    mapping(bytes32 => OnchainData) public orders;

    constructor(address _cowSwapSettlement) {
        cowSwapSettlement = ICoWSwapSettlement(_cowSwapSettlement);
        cowSwapDomainSeparator = CoWSwapEip712.domainSeparator(_cowSwapSettlement);
    }

    /// @dev Function that creates and broadcasts a limit order. The order is paid for when
    /// the caller sends out the transaction. The specific service takes ownership of the new order.
    /// @return orderHash The hash of the CoW Swap order that is created to settle the new ERC20 order.
    function createOrder(IERC20 sellToken, IERC20 buyToken, uint256 sellAmount, uint256 buyAmount, int64 quoteId)
        external
        returns (bytes32 orderHash)
    {
        assert(sellAmount > 0 || buyAmount > 0);
        assert(address(sellToken) != address(0) && sellToken != buyToken);

        sellToken.approve(cowSwapSettlement.vaultRelayer(), sellAmount);

        // Create the order and signatures
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: sellToken,
            buyToken: buyToken,
            receiver: address(this),
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: uint32(block.timestamp) + 3 hours,
            appData: bytes32(0),
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20,
            quoteId: quoteId
        });

        OnchainData memory onchainData = OnchainData(msg.sender, order.validTo);
        OnchainSignature memory signature = OnchainSignature(
            OnchainSigningScheme.Eip1271,
            abi.encodePacked(address(this))
        );

        // The data event field includes extra information needed to settle orders with the CoW Swap API.
        bytes memory data = abi.encodePacked(order.quoteId, onchainData.validTo);
        bytes32 orderHash = broadcastOrder(onchainData.owner, order, signature, data);
        orders[orderHash] = onchainData;

        return orderHash;
    }

    /// @dev EIP1271-compliant onchain signature verification function.
    /// This function is used by the CoW Swap settlement contract to determine if an order that is signed with an
    /// EIP1271 signature is valid. As this contract has approved the vault relayer contract, a valid signature for an
    /// order means that the order can be traded on CoW Swap.
    ///
    /// @param orderHash Hash of the order to be signed. This is the EIP-712 signing hash for the specified order as
    /// defined in the CoW Swap settlement contract.
    /// @param signature Signature byte array. This parameter is unused since as all information needed to verify if an
    /// order is already available onchain.
    /// @return magicValue Either the EIP-1271 "magic value" indicating success (0x1626ba7e) or a different value
    /// indicating failure (0xffffffff).
    function isValidSignature(bytes32 orderHash, bytes memory signature) external view override returns (bytes4) {
        /// @dev the signature parameter is ignored since all information needed to verify the validity
        /// of the order is  already available onchain.
        OnchainData memory orderData = orders[orderHash];
        if (
            (orderData.owner != address(0)) &&
            // solhint-disable-next-line not-rely-on-time
            (orderData.validTo >= block.timestamp)
        ) {
            return CoWSwapEip712.MAGICVALUE;
        } else {
            return bytes4(type(uint32).max);
        }
    }

    /// @dev Emits an event with all information needed to execute an order onchain and returns the corresponding order
    /// hash.
    /// See ICoWSwapOnchainOrders.OrderPlacement for details on the meaning of each parameter.
    /// @return The EIP-712 hash of the order data as computed by the CoW Swap settlement contract.
    function broadcastOrder(
        address sender,
        GPv2Order.Data memory order,
        OnchainSignature memory signature,
        bytes memory data
    ) internal returns (bytes32) {
        emit OrderPlacement(sender, order, signature, data);
        return order.hash(cowSwapDomainSeparator);
    }
}
