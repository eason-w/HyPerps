const { ethers } = require("hardhat");

async function main() {
    const RawHyPerpsHub = await ethers.getContractFactory("HyPerpsHub");
    // const HyPerpsHub = await RawHyPerpsHub.deploy("0x3861e9F29fcAFF738906c7a3a495583eE7Ca4C18", "0x58d7ccbE88Fe805665eB0b6c219F2c27D351E649", "0x29a500d11467A2160a02ABa4f9F94983E458d873", "0xCC737a94FecaeC165AbCf12dED095BB13F037685");
    // await HyPerpsHub.deployed();
    const HyPerpsHub = RawHyPerpsHub.attach("0x125fC4Ff09962b4C2F74B1480fAa13C80E34459c");

    console.log("HyPerpsHub deployed to:", HyPerpsHub.address);



    const RawERC20 = await ethers.getContractFactory("ERC20");
    const USDC = await RawERC20.attach("0x3861e9F29fcAFF738906c7a3a495583eE7Ca4C18");

    // let tx_hash_1 = await USDC.approve(HyPerpsHub.address, 1000000000);
    // await tx_hash_1.wait()
    // console.log(tx_hash_1.hash)
    
    let tx_hash_2 = await HyPerpsHub.depositCollateral(USDC.address, 100000000);
    await tx_hash_2.wait()
    console.log(tx_hash_2.hash)

    let tx_hash_4 = await HyPerpsHub.updateGnosisSpoke("0x1E2879Cf39c22db1d9078Da1DA7e5c44188Db5E7");
    await tx_hash_4.wait()
    console.log(tx_hash_4.hash)
    

    let tx_hash_3 = await HyPerpsHub.sendCollateralAmountToGnosis({value: ethers.utils.parseEther("0.01"), gasLimit: 10000000});
    await tx_hash_3.wait()
    console.log(tx_hash_3.hash)

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });