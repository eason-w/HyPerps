pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import {Router} from "scaffold-eth/node_modules/@hyperlane-xyz/core/contracts/Router.sol";
import "./SingleChainPerpsProtocol.sol";

contract PerpsProtocolRouter is Router {
    SingleChainPerpsProtocol private protocol;

    constructor(
        address _mailbox,
        address _interchainGasPaymaster,
        address _protocolAddress
    ) {
        protocol = SingleChainPerpsProtocol(_protocolAddress);
        _setMailbox(_mailbox);
        _setInterchainGasPaymaster(_interchainGasPaymaster);
    }

    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) external virtual override onlyMailbox onlyRemoteRouter(_origin, _sender) {
        // Decode the function selector from the message
        bytes4 selector = abi.decode(_message, (bytes4));
        
        // Dispatch the message to the appropriate function
        if (selector == protocol.depositLiquidity.selector) {
            (address liquidityType, uint256 amount) = abi.decode(_message[4:], (address, uint256));
            protocol.depositLiquidity(liquidityType, amount);
        } else if (selector == protocol.withdrawLiquidity.selector) {
            (address liquidityType, uint256 amount) = abi.decode(_message[4:], (address, uint256));
            protocol.withdrawLiquidity(liquidityType, amount);
        } else if (selector == protocol.depositCollateral.selector) {
            (address collateralType, uint256 amount) = abi.decode(_message[4:], (address, uint256));
            protocol.depositCollateral(collateralType, amount);
        } else if (selector == protocol.withdrawCollateral.selector) {
            (address collateralType, uint256 amount) = abi.decode(_message[4:], (address, uint256));
            protocol.withdrawCollateral(collateralType, amount);
        } else if (selector == protocol.openPosition.selector) {
            (address assetType, address collateralType, uint256 collateralSize, uint256 leverage, address collateralChain) = abi.decode(_message[4:], (address, address, uint256, uint256, address));
            protocol.openPosition(assetType, collateralType, collateralSize, leverage, collateralChain);
        } else if (selector == protocol.closePosition.selector) {
            (uint256 positionIndex) = abi.decode(_message[4:], (uint256));
            protocol.closePosition(positionIndex);
        } else if (selector == protocol.liquidate.selector) {
            (uint256 positionIndex) = abi.decode(_message[4:], (uint256));
            protocol.liquidate(positionIndex);
        } else {
            revert("Unsupported function selector");
        }
    }
}
