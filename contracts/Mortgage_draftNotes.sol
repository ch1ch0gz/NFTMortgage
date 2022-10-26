
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

/// @title A mortgage NFT contract
/// @author ch1ch0gz
/// @notice This is my first smart contract, lots of improvements to be made
/// @dev Contract under development to allow payment with ERC20, and NFT farming on JPEG'd
contract Mortgage_draft is Ownable, IERC721Receiver {

  event CreateMortgage(address _mortgageCreator,uint256 _mortgageId);
  event DeleteMortgage(address _mortgageCreator,uint256 _mortgageId);
  event RequestMortgageETH(address _mortgageRequestor,uint256 _mortgageId);
  event RepayFullMortgage(address _mortgageRequestor,uint256 _mortgageId);
  event LiquidateMortgage(address _mortgageCreator,uint256 _mortgageId);


  //We use SafeERC20 to be able to support any ERC20 token.
  //Wrappers around ERC20 operations that throw on failure (when the token contract returns false).
  //or do not return anything for example USDT transfer function does not return bool.
  using SafeERC20 for IERC20;
  //Use to count the number of mortgages
  using Counters for Counters.Counter;
  Counters.Counter private _mortgageId;
  //Libraru used to work fixed point numbers
  using PRBMathUD60x18 for uint256;

  // TODO:
  // 3.Tide up comments looking at https://jeancvllr.medium.com/solidity-tutorial-all-about-comments-bc31c729975a

  // LIVE: ongoing mortgages; PENDING: Awaiting to be purchased , PAID: Mortgage fulfilled
  enum MortgageStatus {LIVE, PENDING, LIQUIDATE, PAID}

  //probably better with a struct so I can create several mortgages on the same contract.
  struct MortgageAggrement {
    uint256 price;
    uint256 initialDeposit;
    uint256 interest;
    uint256 balance;
    address nftAddress;
    uint tokenId;
    address payable buyer;
    address payable seller;
    MortgageStatus status;
    uint256 time;
    uint256 startLoan;
    uint256 duration;
  }

  mapping(uint256 => MortgageAggrement) public mortgageTracker;
  //list of nftDespositors and owners
  mapping(address => uint256[]) public nftDepositor;

  // Adding Ownable() to the constructor replaces owner = msg.sender; and declaration  address owner;
  //Wonder if it costs more gas than an owner variable declaration???
  constructor() Ownable(){}

  //This function allows the contract to receive ERC721 but not sure why it works.
  function onERC721Received(address, address, uint256, bytes calldata) external pure returns(bytes4) {
      return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
  }

  function loanValue(uint256 _mortageId) internal view returns(uint256){
    return mortgageTracker[_mortageId].price - mortgageTracker[_mortageId].initialDeposit;
  }

  function getMortgage(uint256 _mortageId) external view returns(MortgageAggrement memory) {
    return mortgageTracker[_mortageId];
  }

  function getFinalBalance(uint256 _mortageId) public view returns(uint256) {
    return monthlyPayments(_mortageId) * mortgageTracker[_mortageId].duration;
  }

  function getRemainingBalance(uint256 _mortageId) public view returns(uint256) {
    return loanValue(_mortageId) - mortgageTracker[_mortageId].balance;
  }

  //This fucntions has initially created to be able to test, probably good use to the front end.
  function getNumberNFTbyDepositor() public view returns (uint) {
     return nftDepositor[msg.sender].length;
  }

  function getNftDepositorValue(uint index) public view returns (uint) {
      return nftDepositor[msg.sender][index];
  }

  //Created by seller
  function createMortgage(uint256 _price, address _nftAddress,uint256 _tokenId,uint256 _initialDeposit,uint256 _interest, uint256 _duration) external {
    MortgageAggrement memory newMortgage = MortgageAggrement(
      { price : _price ,
        initialDeposit: _initialDeposit,
        interest: _interest ,
        balance: 0,
        nftAddress: _nftAddress,
        tokenId: _tokenId,
        //as borrower has not been allocated we set the addres to 0x0 address.
        buyer: payable(address(0)),
        seller : payable(msg.sender),
        status : MortgageStatus.PENDING,
        time: block.timestamp,
        startLoan: block.timestamp,
        //duration expressed in months
        duration: _duration
      });
      _mortgageId.increment();
      mortgageTracker[_mortgageId.current()] = newMortgage;
      //transfer NFT to contract
      IERC721(_nftAddress).safeTransferFrom(msg.sender, address(this), _tokenId);
      nftDepositor[msg.sender].push(_mortgageId.current());
      emit CreateMortgage(msg.sender,_mortgageId.current());

  }

  //Seller function to remove mortgage offer.
  function deleteMortgage(uint256 _mortageId) external {
    require(mortgageTracker[_mortageId].seller == msg.sender);
    IERC721(mortgageTracker[_mortageId].nftAddress).safeTransferFrom( address(this),msg.sender, mortgageTracker[_mortageId].tokenId);
    delete mortgageTracker[_mortageId];
    emit DeleteMortgage(msg.sender, _mortgageId._value);
  }

  //Used by buyer
  function requestMortgageETH(uint256 _mortageId) external payable{
    require(msg.value == mortgageTracker[_mortageId].initialDeposit, 'Initital deposit is not enough');
    require(mortgageTracker[_mortageId].status == MortgageStatus.PENDING, 'Mortage is not available');
    mortgageTracker[_mortageId].status = MortgageStatus.LIVE;
    mortgageTracker[_mortageId].buyer = payable(msg.sender);
    mortgageTracker[_mortageId].time = block.timestamp;
    mortgageTracker[_mortageId].startLoan = block.timestamp;
    mortgageTracker[_mortageId].balance = 0 ;
    mortgageTracker[_mortageId].seller.transfer(msg.value);
    emit RequestMortgageETH(msg.sender, _mortgageId._value);
    //TODO: Send wrap NFT to buyer as proof of ownership? TO DO
  }

  function monthlyPayments(uint256 _mortageId) public view returns(uint256 result){
    uint256 loan = loanValue(_mortageId);
    uint256 interest = mortgageTracker[_mortageId].interest / 100;
    uint256 months = 12*10**18;
    uint256 duration = mortgageTracker[_mortageId].duration; // 604800;
    uint256 monthlyRate = PRBMathUD60x18.div(interest,months);
    uint256 aux = (1*10**18 + monthlyRate).powu(duration);
    uint256 aux1 = aux - 1*10**18;    result = (aux.mul(monthlyRate).div(aux1)).mul(loan);
  }


  //For the POC let's assume we do not take into account not all years are 365
  function repayMonthly(uint256 _mortageId) external payable{
    require(mortgageTracker[_mortageId].status == MortgageStatus.LIVE, "Mortgage is not LIVE");
    require(msg.sender == mortgageTracker[_mortageId].buyer, "Sender is not the buyer of the mortgage");
    require(msg.value == monthlyPayments(_mortageId), "The amount is incorrect");
    require(mortgageTracker[_mortageId].time < block.timestamp && block.timestamp < mortgageTracker[_mortageId].time + 4 weeks,
      "You have missed your mortgage monthly payment or already paid it, check status of loan");
    mortgageTracker[_mortageId].seller.transfer(msg.value);
    mortgageTracker[_mortageId].balance += monthlyPayments(_mortageId);
    mortgageTracker[_mortageId].time = mortgageTracker[_mortageId].time + 4 weeks;
    if(mortgageTracker[_mortageId].balance == monthlyPayments(_mortageId) * mortgageTracker[_mortageId].duration) {
      IERC721(mortgageTracker[_mortageId].nftAddress).safeTransferFrom(address(this),msg.sender, mortgageTracker[_mortageId].tokenId);
      mortgageTracker[_mortageId].status = MortgageStatus.PAID;
      //self drestruct wrapped NFT
    }
  }


  function repayFullMortgage(uint256 _mortageId) external payable{
    require(mortgageTracker[_mortageId].status == MortgageStatus.LIVE, "Mortgage is not LIVE");
    require(msg.sender == mortgageTracker[_mortageId].buyer, "Sender is not the buyer of the mortgage");
    //If earlier payment there is a 5% penalty on top of the amount borrowed
    require(msg.value == getRemainingBalance(_mortageId), "balance numbers do not match ");

    IERC721(mortgageTracker[_mortageId].nftAddress).safeTransferFrom(address(this),msg.sender, mortgageTracker[_mortageId].tokenId);
    mortgageTracker[_mortageId].status = MortgageStatus.PAID;
    emit RepayFullMortgage(msg.sender, _mortgageId._value);
    //self drestruct wrapped NFT
  }

  function mortgageStatus(uint256 _mortageId) external returns (MortgageStatus){
    if(mortgageTracker[_mortageId].status != MortgageStatus.LIVE) {
      return mortgageTracker[_mortageId].status;
    }else {
      // If your next monthly period has passed without you paying you can get liquidated
      if ( block.timestamp > mortgageTracker[_mortageId].time + 4 weeks ) {
        mortgageTracker[_mortageId].status = MortgageStatus.LIQUIDATE;
        return MortgageStatus.LIQUIDATE;
      } else {
        return mortgageTracker[_mortageId].status;
      }
    }
  }


  function liquidateMortgage(uint256 _mortageId) external {
    require(mortgageTracker[_mortageId].status == MortgageStatus.LIQUIDATE);
    require(mortgageTracker[_mortageId].seller == msg.sender);
    IERC721(mortgageTracker[_mortageId].nftAddress).safeTransferFrom(address(this),mortgageTracker[_mortageId].seller, mortgageTracker[_mortageId].tokenId);
    //Perhaps in the future keep a certain percentage in a valut for liquidators.
    emit LiquidateMortgage(msg.sender, _mortgageId._value);
  }

  function claimInterest() external {
    //If any tokens are being farmed in a protocol being able to claim them.
  }

  //To support ERC20 should I want
  function requestMortgageERC20(uint256 mortageId) external {}


  // Destroy only sends ETH to owner
  function destroy() onlyOwner public{
      		selfdestruct(payable(owner()));
  }



  // Receive does not have function keyword, it executes on call to contract with no data
  receive() external payable {}

  //Fallback always receives data and also could receive Ether
  fallback() external payable{}



}
