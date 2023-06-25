pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@hyperlane-xyz/core/contracts/interfaces/IMessageRecipient.sol";
import "@hyperlane-xyz/core/contracts/interfaces/IMailbox.sol";
import "@hyperlane-xyz/core/contracts/interfaces/IInterchainGasPaymaster.sol";

contract HyPerpsSpoke is Ownable{
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

    mapping(address => uint256) public pendingPnl;

    Position[] public positions;
    
    // FOR TESTING PURPOSES: Prices will be set manually by owner, with initial prices also set 
    uint256 USDCPrice = 1;
    uint256 ETHPrice = 1000;
    uint256 BTCPrice = 10000;

    address USDC;
    address wETH;
    address wBTC;

    address mailboxContract;

    bytes32 goerliHub;

    uint32 goerliTestnet = 5;

    // igp of pzkevm: 0x57e69f9cC96Fb9324a196322367520ecE437d896
    // igp of Gnosis: 0x6cA0B6D22da47f091B7613223cD4BB03a2d77918
    // IInterchainGasPaymaster igp = IInterchainGasPaymaster();
    IInterchainGasPaymaster igp;
    uint256 gasAmount = 300000;

    // Events
    event LiquidityDeposited(address indexed user, address indexed liquidityType, uint256 amount);
    event LiquidityWithdrawn(address indexed user, address indexed liquidityType, uint256 amount);
    event CollateralDeposited(address indexed user, address indexed collateralType, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed collateralType, uint256 amount);
    event PositionOpened(address indexed user, address indexed assetType, address indexed collateralType, uint256 collateralSize, uint256 leverage);
    event PositionClosed(address indexed user, uint256 positionIndex, uint256 pnl);
    event PositionLiquidated(address indexed liquidator, address indexed positionOpener, uint256 positionIndex, address indexed collateralType, uint256 collateralSize);
    
    // Goerli addresses: USDC, wETH, wBTC: 0x3861e9F29fcAFF738906c7a3a495583eE7Ca4C18, 0x58d7ccbE88Fe805665eB0b6c219F2c27D351E649, 0x29a500d11467A2160a02ABa4f9F94983E458d873
    // Gnosis mailbox: 0x35231d4c2D8B8ADcB5617A638A0c4548684c7C70
    // Pzkevm mailbox: 0x0282ee93886E62627C863D9Ec88F1408eA7Aeb3B
    // Constructor
    constructor(address _USDC, address _wETH, address _wBTC, address _mailboxContract, address _igp) {
        USDC = _USDC;
        wETH = _wETH;
        wBTC = _wBTC;
        mailboxContract = _mailboxContract;
        igp = IInterchainGasPaymaster(_igp);
    }
    
    // Modifiers
    modifier onlyOpenPosition(uint256 positionIndex) {
        require(positions[positionIndex].isOpen, "Position is not open");
        _;
    }
    // onlyOwner() is also a modifier here, imported from OpenZeppelin

    modifier onlyMailbox() {
        require(msg.sender == address(mailboxContract), "Caller is not the mailbox contract");
        _;
    }

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

    function getPositionInfo(uint256 positionIndex) external view returns (bool, address, address, address, uint256, uint256, uint256, uint256) {
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

    // CrossChain funtions
    function _addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function handle(uint32 _origin, bytes32 _sender, bytes calldata _body) external onlyMailbox {
        (address sender, uint256 _USDCCollateralBalance, uint256 _ETHCollateralBalance, uint256 _BTCCollateralBalance) = abi.decode(_body, (address, uint256, uint256, uint256));

        USDCCollateralBalance[sender] = _USDCCollateralBalance;
        ETHCollateralBalance[sender] = _ETHCollateralBalance;
        BTCCollateralBalance[sender] = _BTCCollateralBalance;
    }

    function sendPnlToGoerli(address _collateralType) external payable {
        uint32 _destinationChain;
        bytes32 _recipient;
        _destinationChain = goerliTestnet;
        _recipient = goerliHub;

        address collateralType = _collateralType;

        uint256 pnl;
        pnl = pendingPnl[msg.sender];

        bytes32 messageId = IMailbox(mailboxContract).dispatch(
            _destinationChain,
            _recipient,
            bytes(abi.encode(msg.sender, pnl, collateralType))
        );

        igp.payForGas{value: msg.value}(
            messageId,
            _destinationChain,
            gasAmount,
            msg.sender 
        );

        pendingPnl[msg.sender] = 0;
        USDCCollateralBalance[msg.sender] = 0;
        ETHCollateralBalance[msg.sender] = 0;
        BTCCollateralBalance[msg.sender] = 0;
    }


    // Public write functions, liquidity and collateral functions
    function depositLiquidity(address liquidityType, uint256 amount) external {
        require(amount > 0, "Invalid deposit amount");
        require((liquidityType == USDC || liquidityType == wETH || liquidityType == wBTC), "Unsupported liquidity type");

        IERC20 liquidityToken = IERC20(liquidityType);
        liquidityToken.transferFrom(msg.sender, address(this), amount);
        
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
        require((collateralType == USDC || collateralType == wETH || collateralType == wBTC), "Unsupported collateral type");

        IERC20 token = IERC20(collateralType);
        token.transferFrom(msg.sender, address(this), amount);
        
        if (collateralType == USDC) {
            USDCCollateralBalance[msg.sender] += amount;
        } else if (collateralType == wETH) {
            ETHCollateralBalance[msg.sender] += amount;
        } else if (collateralType == wBTC) {
            BTCCollateralBalance[msg.sender] += amount; 
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
            require(ETHCollateralBalance[msg.sender] >= amount, "Insufficient wETH collateral balance");
            ETHCollateralBalance[msg.sender] -= amount;
            IERC20(wETH).transfer(msg.sender, amount);
        } else if (collateralType == wBTC) {
            require(BTCCollateralBalance[msg.sender] >= amount, "Insufficient wBTC collateral balance");
            BTCCollateralBalance[msg.sender] -= amount;
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

        uint256 openingPrice;

        if (assetType == wETH) {
            uint256 openingPrice = ETHPrice;
        } else {
            uint256 openingPrice = BTCPrice;
        }

        uint256 liquidationPrice;
        if (collateralType == USDC) {
            liquidationPrice = openingPrice + (openingPrice / leverage * 19/20);
        } else {
            liquidationPrice = openingPrice - (openingPrice / leverage * 21/20);
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

        uint256 closingPrice;
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

        uint256 pnl;
        if (pnl > 0) {
            pendingPnl[msg.sender] += pnl;
        } else {
            pendingPnl[msg.sender] -= pnl;
        }

        position.isOpen = false;

        emit PositionClosed(msg.sender, positionIndex, pnl);
    }
    
    function liquidate(uint256 positionIndex) external onlyOpenPosition(positionIndex) {
        Position storage position = positions[positionIndex];

        uint256 currentPrice;
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
                USDCCollateralBalance[liquidator] += collateralSize*1/20;
                USDCCollateralBalance[positionOpener] -= collateralSize;
            } else if (collateralType == wETH) {
                ETHCollateralBalance[liquidator] += collateralSize*1/20;
                ETHCollateralBalance[positionOpener] -= collateralSize;
            } else if (collateralType == wBTC) {
                BTCCollateralBalance[liquidator] += collateralSize*1/20;
                BTCCollateralBalance[positionOpener] -= collateralSize;
            }

            position.isOpen = false;

            emit PositionLiquidated(liquidator, positionOpener, positionIndex, collateralType, collateralSize);
        }
    }

    // Private write functions
    function updateUSDCPrice(uint256 newUSDCPrice) external onlyOwner() {
        USDCPrice = newUSDCPrice;
    }

    function updateETHPrice(uint256 newETHPrice) external onlyOwner() {
        ETHPrice = newETHPrice;
    }

    function updateBTCPrice(uint256 newBTCPrice) external onlyOwner() {
        BTCPrice = newBTCPrice;
    }

    function updateGoerliHub(address newGoerliHubAddress) external onlyOwner() {
        goerliHub = _addressToBytes32(newGoerliHubAddress);
    }
}