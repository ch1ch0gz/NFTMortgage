const { expect } = require("chai");
const { assert } = require('chai');

describe("Mortgage", function () {
  let mortgage, nft, accounts, tokenURI, signer, signerAddress,add2,
  add2Address, loan,interest,deposit, requestedMortgage;

  beforeEach(async () => {
      accounts = await ethers.provider.listAccounts();
      const Mortgage = await ethers.getContractFactory("Mortgage");
      mortgage = await Mortgage.deploy();
      await mortgage.deployed();

      const NFT = await ethers.getContractFactory("NFT");
      nft = await NFT.deploy();
      await nft.deployed();

      //Deployment costs
      //const deploymentData = mortgage.interface.encodeDeploy();
      //const estimatedGas = await ethers.provider.estimateGas({ data: deploymentData });

      //Another optional
      //Mortgage.getDeployTransaction();
      //const estimatedGas = await ethers.provider.estimateGas(Mortgage.getDeployTransaction().data)
      //console.log("contractEstimate")
      //console.log(estimatedGas);


      signer = ethers.provider.getSigner(0);
      add2 = ethers.provider.getSigner(1);
      [signerAddress, add2Address] = await ethers.provider.listAccounts();

      tokenURI = "https://gateway.ipfs.io/ipfs/QmYgTJDNyD1sBhMxk9m1U13jyjAiyWvDJVBi6fvb6DN9C9";
      loan = ethers.utils.parseEther("10");
      interest = ethers.utils.parseEther("2");
      deposit = ethers.utils.parseEther("3");

  });

  describe('Mortgage', function () {
      const oneEther = ethers.utils.parseEther("1");
      let tokenID;
      beforeEach(async () => {
          //tokenID = await nft.awardItem(accounts[0],tokenURI);
          const tx = await nft.awardItem(accounts[0],tokenURI);
          const receipt = await tx.wait();
          //_mint emits Transfer(address(0), to, tokenId);
          tokenID = parseInt(receipt.logs[0].topics[3]);
      });

      it('should mint a nft', async () => {
          const signerAddress = await nft.ownerOf(tokenID);
          assert.equal(signerAddress.toString(), accounts[0]);
      });

      it('should fail to create a mortgage as contract has not been approve', async () => {
          let failed = false;
          const signerAddress = await nft.ownerOf(tokenID);
          try{
            await mortgage.createMortgage(loan,nft.address,tokenID,deposit,interest,4);
          }
          catch (error) {
            failed = true;
          }
          assert.equal(failed, true, "This test should have failed");
      });

      it('should approve the transfer of a nft to the contract contract', async () => {
          //const tx = await nft.approve(contract.address,tokenID);
          const signerAddress = await nft.ownerOf(tokenID);
          await expect(nft.approve(mortgage.address,tokenID)).to.emit(nft, "Approval")
          .withArgs(accounts[0], mortgage.address,tokenID);

      });

      it('should transfer an nft to contract', async () => {
          let succeded = false;
          await nft.approve(mortgage.address,tokenID);
          try {
            const txResult = await mortgage.createMortgage(loan,nft.address,tokenID,deposit,interest,4)
            succeded = true;
          }
          catch (error) {
            console.log(error);
          }
          const addressOwner = await nft.ownerOf(tokenID);
          assert.equal(succeded, true, "This test should have succeded");
          assert.equal(addressOwner.toString(), mortgage.address)
      });
      describe('Interacting with a mortgage', function () {
        let mortgageNft, receipt, tx, oldBalanceSeller, newBalanceSeller,
        monthlyAmount;
        beforeEach(async () => {
          await nft.approve(mortgage.address,tokenID);
          // 3ETH Price, 1 ETH deposit, 2% interest, 2 months to pay it off
          tx = await mortgage.createMortgage(loan, nft.address, tokenID, deposit, interest, 4)
          receipt = await tx.wait();
          mortgageNft = await mortgage.callStatic.mortgageTracker(1);
        });

        it('should have created a new mortgage', async () => {

            assert.equal(mortgageNft.price.toString(), 10*10**18,"Price does not match");
            assert.equal(mortgageNft.interest.toString(), 2*10**18, "Interest does not match");
            assert.equal(mortgageNft.initialDeposit.toString(), 3*10**18, "Initial deposit does not match");
            assert.equal(mortgageNft.nftAddress, nft.address, "nft address does not match");
            assert.equal(mortgageNft.tokenId, tokenID, "tokenId does not match");
            assert.equal(mortgageNft.duration.toString(), 4 , "length duration does not match");
            //Just some random useful tests below
            //const test1 = await mortgage.callStatic.getNftDepositorValue(0);
            //const test2 = await mortgage.getNftDepositorValue.call(accounts[0],0);

        });

        it('should buyer request a mortgage and send deposit to seller', async() =>{

            oldBalanceSeller = await ethers.provider.getBalance(signerAddress);
            await mortgage.connect(add2).requestMortgageETH(1,{
                value: ethers.utils.parseUnits("3", "ether"),
              });

            requestedMortgage = await mortgage.getMortgage(1);
            assert.equal(requestedMortgage.buyer, add2Address);
            newBalanceSeller = await ethers.provider.getBalance(signerAddress);
            assert.equal(ethers.utils.formatEther((BigInt(newBalanceSeller)- BigInt(oldBalanceSeller)).toString(), "ether"), 3);

        });
        it('should buyer pay first and second month together should fail', async() =>{
            const time = await network.provider.send("evm_mine") ;

            await mortgage.connect(add2).requestMortgageETH(1,{
              value: ethers.utils.parseUnits("3", "ether"),
            });
            oldBalanceSeller = await ethers.provider.getBalance(signerAddress);
            monthlyAmount = await mortgage.monthlyPayments(1);

            await mortgage.connect(add2).repayMonthly(1,{value: monthlyAmount.toString()});
            newBalanceSeller = await ethers.provider.getBalance(signerAddress);
            assert.equal(newBalanceSeller, oldBalanceSeller.toBigInt() + monthlyAmount.toBigInt());
            //Try to pay again on the same month should be rejected
            await expect(mortgage.connect(add2).repayMonthly(1,{value: monthlyAmount.toString()})).to.be.reverted;

            const time1 = await network.provider.send("evm_increaseTime", [2419200])
            await mortgage.connect(add2).repayMonthly(1,{value: monthlyAmount.toString()});

        });

        it('should buyer pay all month and earn nft', async() =>{
            await network.provider.send("evm_mine");
            let myMortgage;
            let myDuration;
            let myMortgageStatus;
            const finalBalance = await mortgage.getFinalBalance(1);

            await mortgage.connect(add2).requestMortgageETH(1,{
              value: ethers.utils.parseUnits("3", "ether"),
            });

            myMortgage = await mortgage.getMortgage(1);
            myDuration = myMortgage.duration;

            monthlyAmount = await mortgage.monthlyPayments(1);

            for(let i = 0; i< myDuration; i++) {
              await mortgage.connect(add2).repayMonthly(1,{value: monthlyAmount.toString()});
              await network.provider.send("evm_increaseTime", [2419200]);
            }
            const newAddressOwner = await nft.ownerOf(tokenID);
            myMortgage = await mortgage.getMortgage(1);
            myMortgageStatus = await mortgage.callStatic.mortgageStatus(1);

            assert.equal(add2Address.toString(), newAddressOwner);
            assert.equal(myMortgage.status, myMortgageStatus);

        });

        it('should buyer pay all after one month and earn nft', async() =>{
          await network.provider.send("evm_mine");
          let myMortgage;
          let myDuration;
          let remainingBalance;
          let newAddressOwner;
          const finalBalance = await mortgage.getFinalBalance(1);

          await mortgage.connect(add2).requestMortgageETH(1,{
            value: ethers.utils.parseUnits("3", "ether"),
          });
          newAddressOwner = await nft.ownerOf(tokenID);
          myMortgage = await mortgage.getMortgage(1);
          monthlyAmount = await mortgage.monthlyPayments(1);

          await mortgage.connect(add2).repayMonthly(1,{value: monthlyAmount.toString()});
          await network.provider.send("evm_increaseTime", [2419200]);
          myMortgage = await mortgage.getMortgage(1)
          remainingBalance = await mortgage.getRemainingBalance(1);

          await mortgage.connect(add2).repayFullMortgage(1,{value: remainingBalance.toString()});
          newAddressOwner = await nft.ownerOf(tokenID);
          assert.equal(add2Address.toString(), newAddressOwner);
        });

        it('should buyer fail to pay first month and get liquidated', async() =>{
          let myMortgageStatus, newAddressOwner;
          await network.provider.send("evm_mine");
          await mortgage.connect(add2).requestMortgageETH(1,{
            value: ethers.utils.parseUnits("3", "ether"),
          });
          await mortgage.mortgageStatus(1);
          myMortgageStatus = await mortgage.callStatic.mortgageStatus(1);
          await network.provider.send("evm_increaseTime", [2419200]);

          await mortgage.mortgageStatus(1);
          myMortgageStatus = await mortgage.callStatic.mortgageStatus(1);

          //Now mortgage can be liquidated
          await mortgage.liquidateMortgage(1);
          newAddressOwner = await nft.ownerOf(tokenID);
          assert.equal(signerAddress.toString(), newAddressOwner);

        });

        it("it should selfDestroy when called.", async function () {
          //Lets destroy the contract
          await mortgage.destroy();
          assert(ethers.provider.getCode(mortgage.address), '0x');
        });

      });

/*// TODO:
  deleteMortgage
  requestMortgageETH
  repayMonthly
  repayFullMortgage

*/
  });

});
