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

    mapping(address => uint256) public liquidityPoolShare;

    Position[] public positions;
    
    // FOR TESTING PURPOSES: Prices will be set manually by owner, with initial prices also set 
    uint256 USDCPrice = 1;
    uint256 ETHPrice = 1000;
    uint256 BTCPrice = 10000;

    address USDC;
    address wETH;
    address wBTC;

    // Events
    event LiquidityDeposited(address indexed user, address indexed liquidityType, uint256 amount);
    event LiquidityWithdrawn(address indexed user, address indexed liquidityType, uint256 amount);
    event CollateralDeposited(address indexed user, address indexed collateralType, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed collateralType, uint256 amount);
    event PositionOpened(address indexed user, address indexed assetType, address indexed collateralType, uint256 collateralSize, uint256 leverage);
    event PositionClosed(address indexed user, uint256 positionIndex, uint256 pnl);
    event PositionLiquidated(address indexed liquidator, address indexed positionOpener, uint256 positionIndex, address indexed collateralType, uint256 collateralSize);
    
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
    function getTotalUSDCollateral(address user) external view returns (uint256) {
        uint256 totalCollateral = 0;
        totalCollateral += USDCCollateralBalance[user];
        totalCollateral += ETHCollateralBalance[user] * ETHPrice;
        totalCollateral += BTCCollateralBalance[user] * BTCPrice;
        return totalCollateral;
    }
    
    function getCollateralBalances(address user) external view returns (uint256[3] memory) {
        uint256[3] memory collateralBalances;
        collateralBalances[0] = USDCCollateralBalance[user];
        collateralBalances[1] = ETHCollateralBalance[user];
        collateralBalances[2] = BTCCollateralBalance[user];
        
        return collateralBalances;
    }

    function getLiquidityPoolShares(address user) external view returns (uint256) {
        return liquidityPoolShare[user];
    }

    function getPositionInfo(uint256 positionIndex) external view returns (bool, address, address, uint256, uint256, uint256, uint256, uint256) {
        Position storage position = positions[positionIndex];

        return (
            position.isOpen,
            position.positionOpener,
            position.collateralType,
            position.assetType,
            position.collateralSize,
            position.leverage,
            position.openingPrice,
            position.liquidationPrice
        );
    }


    // Public write functions, liquidity and collateral functions
    function depositLiquidity(address liquidityType, uint256 amount) external {
        require(amount > 0, "Invalid deposit amount");
        require((liquidityType == USDC || liquidityType == wETH || liquidityType == wBTC), "Unsupported liquidity type");

        IERC20 liquidityToken = IERC20(liquidityType);
        liquidityToken.transferFrom(msg.sender, this(address), amount);
        
        if (liquidityType == USDC) {
            liquidityPoolShare[msg.sender] += (amount);
        } else if (liquidityType == wETH) {
            liquidityPoolShare[msg.sender] += (amount*ETHPrice);
        } else if (liquidityType == wBTC) {
            liquidityPoolShare[msg.sender] += (amount*BTCPrice); 
        }

        emit LiquidityDeposited(msg.sender, liquidityType, amount);
    }   

    function withdrawLiquidity(address liquidityType, uint256 amount) external {
        require(amount > 0, "Invalid withdraw amount");
        require((liquidityType == USDC || liquidityType == wETH || liquidityType == wBTC), "Unsupported liquidity type");
        require(liquidityPoolShare[msg.sender] >= amount, "Insufficient USDC collateral balance");

        liquidityPoolShare[msg.sender] -= amount;

        if (liquidityType == USDC) {
            IERC20(USDC).transfer(msg.sender, amount);
        } else if (liquidityType == wETH) {
            IERC20(wETH).transfer(msg.sender, (amount/ETHPrice));
        } else if (liquidityType == wBTC) {
            IERC20(wBTC).transfer(msg.sender, (amount/BTCPrice));
        }

        emit LiquidityWithdrawn(msg.sender, liquidityType, amount);
    }

    function depositCollateral(address collateralType, uint256 amount) external {
        require(amount > 0, "Invalid deposit amount");
        require((collateralType == USDC || collateralType == wETH || collateralType == wBTC), "Unsupported liquidity type");

        IERC20 token = IERC20(collateralType);
        token.transferFrom(msg.sender, this(address), amount);
        
        if (collateralType == USDC) {
            USDCCollateralBalance[msg.sender] += amount;
        } else if (collateralType == wETH) {
            wETHCollateralBalance[msg.sender] += amount;
        } else if (collateralType == wBTC) {
            wBTCCollateralBalance[msg.sender] += amount; 
        }

        emit CollateralDeposited(msg.sender, collateralType, amount);
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

        emit CollateralWithdrawn(msg.sender, collateralType, amount);
    }

    // Public write functions, position manager collateral functions
    function openPosition(address assetType, address collateralType, uint256 collateralSize, uint256 leverage, address collateralChain) external {
        require(collateralSize > 0, "Invalid collateral size");
        require(leverage > 0 && leverage <= 10, "Invalid leverage value");
        if (collateralType == USDC) {
            require(assetType != USDC);
        } else {
            require(collateralType == assetType);
        }

        uint256 positionSize = collateralSize * leverage;

        if (assetType == wETH) {
            uint256 openingPrice = ETHPrice;
        } else {
            uint256 openingPrice = BTCPrice;
        }

        uint256 liquidationPrice;
        if (collateralType == USDC) {
            liquidationPrice = openingPrice + (openingPrice / leverage * 0.95);
        } else {
            liquidationPrice = openingPrice - (openingPrice / leverage * 1.05);
        }

        positions.push(Position({
            isOpen: true,
            positionOpener: msg.sender,
            collateralType: collateralType,
            assetType: assetType,
            collateralSize: collateralSize,
            leverage: leverage,
            openingPrice: openingPrice,
            liquidationPrice: liquidationPrice
        }));

        if (collateralType == USDC) {
            USDCCollateralBalance[msg.sender] -= collateralSize;
        } else if (collateralType == wETH) {
            ETHCollateralBalance[msg.sender] -= collateralSize;
        } else if (collateralType == wBTC) {
            BTCCollateralBalance[msg.sender] -= collateralSize;
        }

        emit PositionOpened(msg.sender, assetType, collateralType, collateralSize, leverage);
    }
    
    function closePosition(uint256 positionIndex) external onlyOpenPosition(positionIndex) {
        Position storage position = positions[positionIndex];

        if (position.assetType == wETH) {
            uint256 closingPrice = ETHPrice;
        } else {
            uint256 closingPrice = BTCPrice;
        }

        if (position.collateralType == USDC) {
            uint256 pnl = ((position.openingPrice / closingPrice - 1) * position.leverage) * position.collateralSize;
        } else {
            uint256 pnl = ((closingPrice / position.openingPrice - 1) * position.leverage) * position.collateralSize;
        }

        if (pnl > 0) {
            if (position.collateralType == USDC) {
                USDCCollateralBalance[msg.sender] += pnl;
            } else if (position.collateralType == wETH) {
                ETHCollateralBalance[msg.sender] += pnl;
            } else if (position.collateralType == wBTC) {
                BTCCollateralBalance[msg.sender] += pnl;
            }
        } else {
            if (position.collateralType == USDC) {
                USDCCollateralBalance[msg.sender] -= pnl;
            } else if (position.collateralType == wETH) {
                ETHCollateralBalance[msg.sender] -= pnl;
            } else if (position.collateralType == wBTC) {
                BTCCollateralBalance[msg.sender] -= pnl;
            }
        }

        position.isOpen = false;

        emit PositionClosed(msg.sender, positionIndex, pnl);
    }
    
    function liquidate(uint256 positionIndex) external onlyOpenPosition(positionIndex) {
        Position storage position = positions[positionIndex];

        if (position.assetType == wETH) {
            uint256 currentPrice = ETHPrice;
        } else {
            uint256 currentPrice = BTCPrice;
        }

        if ((position.collateralType == USDC && currentPrice >= position.liquidationPrice) ||
            (position.collateralType != USDC && currentPrice <= position.liquidationPrice)) {
            address liquidator = msg.sender;
            address positionOpener = position.positionOpener;
            address collateralType = position.collateralType;
            uint256 collateralSize = position.collateralSize;

            if (collateralType == USDC) {
                USDCCollateralBalance[liquidator] += collateralSize*0.05;
                USDCCollateralBalance[positionOpener] -= collateralSize;
            } else if (collateralType == wETH) {
                ETHCollateralBalance[liquidator] += collateralSize*0.05;
                ETHCollateralBalance[positionOpener] -= collateralSize;
            } else if (collateralType == wBTC) {
                BTCCollateralBalance[liquidator] += collateralSize*0.05;
                BTCCollateralBalance[positionOpener] -= collateralSize;
            }

            position.isOpen = false;

            emit PositionLiquidated(liquidator, positionOpener, positionIndex, collateralType, collateralSize);
        }
    }

    // Private write functions
    function updateUSDCPrice(uint256 newUSDCPrice) external onlyOwner {
        USDCPrice = newUSDCPrice;
    }

    function updateETHPrice(uint256 newETHPrice) external onlyOwner {
        ETHPrice = newETHPrice;
    }

    function updateBTCPrice(uint256 newBTCPrice) external onlyOwner {
        BTCPrice = newBTCPrice;
    }

}
