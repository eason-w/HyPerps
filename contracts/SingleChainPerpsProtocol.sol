pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "./pythTestnetPriceFetcher.sol";
import "scaffold-eth/node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "scaffold-eth/node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SingleChainPerpsProtocol{

    // Data types
    struct Position {
        bool isOpen;

        address positionOpener;
        address collateralType;
        address assetType;

        uint256 collateralSize;
        uint256 leverage;
        uint256 openingPrice;
        uint256 liquidationPrice;
    }
    
    mapping(address => uint256) public USDCCollateralBalance;
    mapping(address => uint256) public ETHCollateralBalance;
    mapping(address => uint256) public BTCCollateralBalance;

    Position[] public positions;
    
    // FOR TESTING PURPOSES: Prices will be set manually by owner, with initial prices also set 
    uint256 USDCPrice = 1;
    uint256 ETHPrice = 1000;
    uint256 BTCPrice = 10000;

    address USDC;
    address wETH;
    address wBTC;
    
    // Constructor
    constructor(address _USDC, address _wETH, address _wBTC) {
        USDC = _USDC;
        wETH = _wETH;
        wBTC = _wBTC;
    }
    
    // Modifiers
    modifier onlyOpenPosition(uint256 positionIndex) {
        require(positions[positionIndex].isOpen, "Position is not open");
        _;
    }
    // onlyOwner() is also a modifier here, imported from OpenZeppelin

    // Read functions
    

    // Public write functions
    function depositCollateral(address collateralType, uint256 amount) external {
        require(amount > 0, "Invalid deposit amount");
        require((collateralType == USDC || collateralType == wETH || collateralType == wBTC), "Unsupported collateral type");

        IERC20 token = IERC20(collateralType);
        token.transferFrom(msg.sender, this(address), amount);
        
        if (collateralType == USDC) {
            USDCCollateralBalance[msg.sender] += amount;
        } else if (collateralType == wETH) {
            wETHCollateralBalance[msg.sender] += amount;
        } else if (collateralType == wBTC) {
            wBTCCollateralBalance[msg.sender] += amount; 
        }
    }

    function withdrawCollateral(address collateralType, uint256 amount) external {
        require(amount > 0, "Invalid withdrawal amount");
        require((collateralType == USDC || collateralType == wETH || collateralType == wBTC), "Unsupported collateral type");

        if (collateralType == USDC) {
            require(USDCCollateralBalance[msg.sender] >= amount, "Insufficient USDC collateral balance");
            USDCCollateralBalance[msg.sender] -= amount;
            IERC20(USDC).transfer(msg.sender, amount);
        } else if (collateralType == wETH) {
            require(wETHCollateralBalance[msg.sender] >= amount, "Insufficient wETH collateral balance");
            wETHCollateralBalance[msg.sender] -= amount;
            IERC20(wETH).transfer(msg.sender, amount);
        } else if (collateralType == wBTC) {
            require(wBTCCollateralBalance[msg.sender] >= amount, "Insufficient wBTC collateral balance");
            wBTCCollateralBalance[msg.sender] -= amount;
            IERC20(wBTC).transfer(msg.sender, amount);
        }
    }

    
    function openPosition(bytes32 assetType, bytes32 collateralType, uint256 collateralSize, uint256 leverage, bytes32 collateralChain) external {
        require(supportedCollateralTypes[collateralType], "Unsupported collateral type");
        require(collateralBalances[msg.sender] >= collateralSize, "Insufficient collateral balance");
        require(leverage <= 10, "Invalid leverage");
        
        uint256 positionSize = collateralSize * leverage;
        uint256 openingPrice = priceOracle.getPrice(assetType);
        uint256 liquidationPrice = openingPrice * (openingPrice / (leverage * 10 / 100));
        
        positions[positionCount] = Position({
            isOpen: true,
            owner: msg.sender,
            assetType: assetType,
            collateralType: collateralType,
            collateralSize: collateralSize,
            leverage: leverage,
            openingPrice: openingPrice,
            liquidationPrice: liquidationPrice
        });
        
        collateralBalances[msg.sender] -= collateralSize;
        positionCount++;
    }
    
    function closePosition(uint256 positionIndex, bytes32 collateralChain) external onlyOpenPosition(positionIndex) {
        Position storage position = positions[positionIndex];
        require(position.owner == msg.sender, "You are not the owner of this position");
        
        uint256 closingPrice = priceOracle.getPrice(position.assetType);
        uint256 pnl = ((closingPrice / position.openingPrice - 1) * position.leverage) * position.collateralSize;
        
        collateralBalances[msg.sender] += position.collateralSize + pnl;
        position.isOpen = false;
    }
    
    function liquidate(uint256 positionIndex, bytes32 collateralChain) external {
        Position storage position = positions[positionIndex];
        require(position.isOpen, "Position is not open");
        
        uint256 currentPrice = priceOracle.getPrice(position.assetType);
        require(
            (position.collateralType == "USDC" && currentPrice < position.liquidationPrice) ||
            (position.collateralType != "USDC" && currentPrice > position.liquidationPrice),
            "Position is not eligible for liquidation"
        );
        
        uint256 pnl = ((currentPrice / position.openingPrice - 1) * position.leverage) * position;
    }

    // Private write functions

}
