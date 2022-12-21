import {Signer} from "ethers";
import {RPC} from "../typechain-types";

const { expect } = require("chai");
const { ethers } = require("hardhat");

const pick1 = 1; // rock
const seed1 = "f".repeat(16);
console.log(ethers.utils.formatBytes32String(seed1))
console.log(    ethers.utils.solidityPack(
    ["uint256", "bytes32"],
    [pick1, ethers.utils.formatBytes32String(seed1)]
))
const encryptedPick = ethers.utils.keccak256(
    ethers.utils.solidityPack(
        ["uint256", "bytes32"],
        [pick1, ethers.utils.formatBytes32String(seed1)]
    )
);

describe("InterContract", function(){
    let rps: RPC;
    let account: Signer;
    let opponent: Signer;

    beforeEach(async () => {
        [account, opponent] = await ethers.getSigners();

        const rpsFactory = await ethers.getContractFactory("RPC");
        rps = await rpsFactory.deploy();
        await rps.deployed();
    });

    describe("Rps tests", () => {
        it("should create game", async () => {
            const gamesTotalBefore = await rps.connect(account).gameCount();
            expect(gamesTotalBefore).to.equal(0);

            const gameId = await rps.connect(account).createPublic(
                encryptedPick,
                {
                    value: ethers.utils.parseEther("0.1")
                }
            );

            const gamesTotalAfter = await rps.gameCount();
            expect(gamesTotalAfter).to.equal(1);
        });

        it("commit for opponent", async () => {
            const gamesTotalBefore = await rps.connect(account).gameCount();
            expect(gamesTotalBefore).to.equal(0);

            const gameId = await rps.connect(account).createPrivate(
                encryptedPick,
                opponent.getAddress(),
                {
                    value: ethers.utils.parseEther("1")
                }
            );

            expect(
                () => rps.connect(opponent).joinGame(gameId.value, encryptedPick)
            ).to.not.throw();
        });


        it("commit and correct reveal", async () => {
            const gameId = await rps.connect(account).createPrivate(
                encryptedPick,
                opponent.getAddress(),
                {
                    value: ethers.utils.parseEther("1")
                }
            );

            await rps.connect(opponent).joinGame(gameId.value, encryptedPick);

            expect(() => rps.connect(account).revealPick(
                gameId.value,
                pick1,
                seed1
            )).to.not.throw();
        });
    });
});