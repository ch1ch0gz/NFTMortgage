//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/**
 Contract only used for testing
*/
interface IRouter {
  function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);
}
