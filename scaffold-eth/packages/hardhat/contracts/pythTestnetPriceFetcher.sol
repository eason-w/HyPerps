pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "scaffold-eth/node_modules/@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "scaffold-eth/node_modules/@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "scaffold-eth/node_modules/@pythnetwork/pyth-sdk-solidity/IPythEvents.sol";


contract pythPriceFetcher{
    IPyth pyth;

    // Pyth Price Feed IDs on Testnet
    bytes32 testnetUSDCPriceId = 0x41f3625971ca2ed2263e78573fe5ce23e13d2558ed3f2e47ab0f84fb9e7ae722;
    bytes32 testnetETHPriceId = 0xca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6;
    bytes32 testnetBTCPriceId = 0xf9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b;

    // // Pyth Price Feed IDs on Mainnet
    // bytes32 mainnetUSDCPriceId = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    // bytes32 mainnetETHPriceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    // bytes32 mainnetBTCPriceId = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

    // Latest price uint
    int256 USDCPrice;
    int256 ETHPrice;
    int256 BTCPrice;

    // Gnosis mainnet: 0x2880ab155794e7179c9ee2e38200202908c17b43
    // Goerli testnet: 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C
    // Polygon zkevm testnet: 0xd54bf1758b1c932f86b178f8b1d5d1a7e2f62c2e
    constructor(address _pyth) {
        pyth = IPyth(_pyth);
    }

    // Viewable functions to view the latest updated price
    function viewUSDCPrice() public view returns(int256) {
        return USDCPrice;
    }

    function viewETHPrice() public view returns(int256) {
        return ETHPrice;
    }

    function viewBTCPrice() public view returns(int256) {
        return BTCPrice;
    }

    // Writeable functions to update the prices
    function getUSDCPrice(bytes[] calldata pythUpdateData) external payable{
        uint updateFee = pyth.getUpdateFee(pythUpdateData);
        pyth.updatePriceFeeds{value: updateFee}(pythUpdateData);

        PythStructs.Price memory currentUSDCPrice = pyth.getPrice(testnetUSDCPriceId);
        USDCPrice = int256(currentUSDCPrice.price);
    }

    function getETHPrice(bytes[] calldata pythUpdateData) external payable{
        uint updateFee = pyth.getUpdateFee(pythUpdateData);
        pyth.updatePriceFeeds{value: updateFee}(pythUpdateData);

        PythStructs.Price memory currentETHPrice = pyth.getPrice(testnetETHPriceId);
        ETHPrice = int256(currentETHPrice.price);
    }
    
    function getBTCPrice(bytes[] calldata pythUpdateData) external payable{
        uint updateFee = pyth.getUpdateFee(pythUpdateData);
        pyth.updatePriceFeeds{value: updateFee}(pythUpdateData);

        PythStructs.Price memory currentBTCPrice = pyth.getPrice(testnetBTCPriceId);
        BTCPrice = int256(currentBTCPrice.price);
    }
}