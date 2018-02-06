pragma solidity ^0.4.13;

contract TokenReceiver {
  function tokenFallback(address _sender, address _origin, uint _value, bytes _data) public returns (bool ok);
}
