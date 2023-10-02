const TESTDOGE = artifacts.require('TESTDOGE');
const { assert } = require('chai');

contract('TESTDOGE', (accounts) => {
    let TESTDOGEInstance;
    let owner = accounts[0];
    let walletB = accounts[1];
    let walletC = accounts[2];
    
    before(async () =>{        
       TESTDOGEInstance = await TESTDOGE.deployed();
       
    });

    it(`1. Just to make sure this works...`, async function () {

        // Get token name
        let getName = await TESTDOGEInstance.name.call({from: owner});
        assert.equal(getName, "TEST DOGE", "Fetches name of coin from contract");

    });

    it(`2. Check total supply.`, async function () {

        // Get total token supply(in contract)
        getTotalSupply = await TESTDOGEInstance.totalSupply.call({from: owner});
        // Total supply should be 10,000,000,000
        assert.equal(getTotalSupply, 10000000000, "Fetches the total coin supply");

    });

    it(`3. Check balance of owner wallet(accounts[0])`, async function () {

        // Get balance of owner address
        ownerSupply = await TESTDOGEInstance.balanceOf.call(owner, {from: owner});
        // Owner balance should be 10,000,000,000
        assert.equal(ownerSupply, 10000000000, "Owner wallet owns 100% of all tokens");

    });

    it(`4. Send 50% of tokens to walletB and 20% of tokens to walletC`, async function () {

        // Find 50% of owner's total balance
        let fiftyPercent = getTotalSupply * 0.5;
        let twentyPercent = getTotalSupply * 0.2;
        // Send 50% of owner's tokens to walletB
        await TESTDOGEInstance.transfer(walletB, fiftyPercent, {from: owner});
        // Send 20% of total tokens to walletC
        await TESTDOGEInstance.transfer(walletC, twentyPercent, {from: walletB});
        
        let bSupply = await TESTDOGEInstance.balanceOf.call(walletB, {from: owner});
        // walletB new balance
        console.log(bSupply.toString())
        assert.equal(bSupply, 3012048192, "WalletB balance is 50% - 20% + reflection");

    });

    it(`5. Check WalletC balance`, async function () {

        // Check walletC balance    
        let cSupply = await TESTDOGEInstance.balanceOf.call(walletC, {from: owner});
        // Wallet C's new balance
        console.log(cSupply.toString())
        assert.equal(cSupply, 1807228915, "C balance is 20% (less 2% + reflection)");
    });

    it(`6. Check that owner recieved reflection`, async function () {

        // Get balance of owner address
        ownerSupply = await TESTDOGEInstance.balanceOf.call(owner, {from: owner});
        // owner's new balance
        console.log(ownerSupply.toString())
        assert.equal(ownerSupply, 5020080321, "Owner balance is 50% + reflection");

    });

    it(`7. Check approve`, async () => {
        await TESTDOGEInstance.approve(accounts[1], 1000);
    });

    it(`8. Check increaseAllowance`, async () => {
        assert.notEqual(accounts[5], '0x0', 'spender address can not be zero address');
        await TESTDOGEInstance.increaseAllowance(accounts[5], 1000);
    });

    it(`9. Check decreaseAllowance`, async () => {
        assert.notEqual(accounts[5], '0x0', 'spender address can not be zero address');
        await TESTDOGEInstance.decreaseAllowance(accounts[5], 100);
    });

    it(`10. Check excludeFromFee`, async () => {
        assert.equal(accounts[1], owner, 'Only owner can access this function.');
        await TESTDOGEInstance.excludeFromFee(accounts[1]);
    });

    it(`11. Check includeInFee`, async () => {
        assert.equal(accounts[1], owner, 'Only owner can access this function.');
        await TESTDOGEInstance.includeInFee(accounts[1]);
    });

});