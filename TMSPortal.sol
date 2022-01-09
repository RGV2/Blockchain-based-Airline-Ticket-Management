// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./TMSAirline.sol";

contract TMSPortal {
    //deploy airline first then deploy TMSPortal for testing.
    address private airlineContract;
    address private admin;
    address[] private customers;
    TMSAirline airline;
    
    mapping(address => address[]) bookingHistory;
    
    constructor(address _airlineContract) {
        require(_airlineContract != address(0), "Error: Invalid address for airline contract");
        airlineContract = _airlineContract;
        airline = TMSAirline(airlineContract);
        admin = msg.sender;
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Error: Only admin can do this action");
        _;
    }
    
    function bookTicket(uint flightNo, string calldata flightDate) public returns (address ticketAddr) {
        customers.push(msg.sender);
        address ticket = airline.createTicket(flightNo, flightDate, msg.sender);
        bookingHistory[msg.sender].push(ticket);
        return ticket;
    }
    
    function getMyBookings() public view returns(address[] memory){
        return bookingHistory[msg.sender];
    }
    
    function setAirline(address _airlineContract) public onlyAdmin {
        require(_airlineContract != address(0), "Error: Invalid address for airline contract");
        airlineContract = _airlineContract;
        airline = TMSAirline(airlineContract);
    }
    
    function getAirline() public view onlyAdmin returns (address) {
        return airlineContract;
    }
    
    function searchFlight( string calldata origin, string calldata dest, string calldata travelDate) public view returns (uint) {
        TMSAirline tmsairline = TMSAirline(airlineContract);
        uint flightNo = tmsairline.searchFlight(  origin,  dest, travelDate);
        return flightNo;
    }
}
