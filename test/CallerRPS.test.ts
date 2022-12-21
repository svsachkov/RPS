import {Signer} from "ethers";
import {CallerRPS, RPC} from "../typechain-types";

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Test", function(){
    let caller: CallerRPS;
    let rps: RPC;
    let account: Signer;

    beforeEach(async () => {
        [account] = await ethers.getSigners();

        const rpsFactory = await ethers.getContractFactory("RPC");
        rps = await rpsFactory.deploy();
        await rps.deployed();

        const callerFactory = await ethers.getContractFactory("CallerRPS");
        caller = await callerFactory.deploy(rps.address);
        await caller.deployed();
    });

    describe("Caller tests", () => {
        it("should create game", async () => {

            expect(await rps.gameCount()).to.equal(0);

            await caller.connect(account).callFunction(
                "0xa4cb272a1e397e5e8e2eb92da9620f56e838f90ccbff21f7610d41027ae09b41"
            );

            expect(await rps.connect(account).gameCount()).to.equal(1);
        });
    });
});