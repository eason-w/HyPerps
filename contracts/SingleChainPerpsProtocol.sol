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

        if (assetType == ETH) {
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
    }
    
    function closePosition(uint256 positionIndex) external onlyOpenPosition(positionIndex) {
        Position storage position = positions[positionIndex];

        uint256 closingPrice = PythTestnetPriceFetcher.getPrice(position.assetType, msg.sender);
        uint256 pnl = ((closingPrice / position.openingPrice - 1) * position.leverage) * position.collateralSize;

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
    }
    
    function liquidate(uint256 positionIndex, address destinationChain) external {
        Position storage position = positions[positionIndex];

        uint256 currentPrice = PythTestnetPriceFetcher.getPrice(position.assetType, msg.sender);

        if ((position.collateralType == USDC && currentPrice <= position.liquidationPrice) ||
            (position.collateralType != USDC && currentPrice >= position.liquidationPrice)) {
            address liquidator = msg.sender;
            address positionOpener = position.positionOpener;
            address collateralType = position.collateralType;
            uint256 collateralSize = position.collateralSize;

            if (collateralType == USDC) {
                USDCCollateralBalance[liquidator] += collateralSize;
                USDCCollateralBalance[positionOpener] -= collateralSize;
            } else if (collateralType == wETH) {
                ETHCollateralBalance[liquidator] += collateralSize;
                ETHCollateralBalance[positionOpener] -= collateralSize;
            } else if (collateralType == wBTC) {
                BTCCollateralBalance[liquidator] += collateralSize;
                BTCCollateralBalance[positionOpener] -= collateralSize;
            }

            position.isOpen = false;
        }
    }

    // Private write functions

}
