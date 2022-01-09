// SPDX-License-Identifier: MIT
// Author: Ashhar (RGV2)

pragma solidity >=0.8.0 <0.9.0;

import "./TMSTicket.sol";
import "./AirlineLibraries.sol";

contract TMSAirline {

    event Error(string error);
    event AirlineCreated(string _airlineName, string _airlineSymbol);
    event StatusUpdated(uint _flightNumber, string _flightDate, FlightStatus _flightStatus, address _address);
    event FlightCreated(uint _flightNumber, address _address);
    event FlightModified(uint _flightNumber, address _address);
    event FlightBalance(uint _airlineBalance);
    event PenaltyPaid(uint _totalPenaltyAmount);
    event TicketBooked(address _ticketContract);

    address payable airlineAdmin = payable(0);
    address airlineAccount = address(0);

    enum FlightStatus {SCHEDULED, ONTIME, DELAYED, CANCELLED, DEPARTED, ARRIVED}
    enum Aircraft {Airbus_320, Boeing_787_Dreamliner}

    string public airlineName;
    string public airlineSymbol;

    // Total amount received for all flights
    uint private airlineBalance;

    // Total panelty paid for all flights
    uint private totalPenaltyAmount;

    // Airlines data structures
    struct flightData {
        uint flightNumber;
        string source;
        string destination;
        uint fixedBasePrice;
        uint totalSeats;
        uint totalPassengers;
        uint256 departureTime;
        uint256 arrivalTime;
        uint256 duration;
        string flightDate;
        address[] allTicketsInTheFlight; //lists of ticket contracts in a flight
        mapping(address => bool) ticketExists;
        Aircraft aircraft;
        FlightStatus flightStatus;
        mapping(uint8 => address) reservedSeats;
    }

    // Assumption: There will be a single flight in a day with a specific flight number.
    // Flight history map: [flight number -> date -> flight data]
    mapping (uint => mapping (string => flightData)) private allFlightDetailsMap;
    uint[] private allFlights;

    // user -> contract -> flight data
    mapping (address => mapping (address => flightData)) private userBookingHistoryMap;

    // flight -> isFlightActive
    mapping (uint => bool) private isFlightActive;

    // Modifiers - START
    modifier onlyAirline() {
        require((airlineAccount != address(0)), "Only the Airline can do this & Airline Accounts are not setup yet.");
        require((msg.sender == airlineAccount) || (msg.sender == airlineAdmin), "Only the Airline can do this.");
        _;
    }

    modifier onlyAirlineAdmin() {
        require(msg.sender == airlineAdmin, "Only the Airline Admin can do this.");
        _;
    }

    modifier flightActive(uint _flightNumber) {
        require (isFlightActive[_flightNumber] == true, "Currently the flight is inactive!");
        _;
    }

    modifier flightInactive(uint _flightNumber) {
        require (isFlightActive[_flightNumber] == false, "Currently the flight is active!");
        _;
    }

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "Invalid address!");
        _;
    }

    modifier flightAvailability(uint _flightNumber, string memory _flightDate) {
        require (allFlightDetailsMap[_flightNumber][_flightDate].flightNumber == _flightNumber, "No flight found!");
        _;
    }

    modifier newFlightAvailability(uint _flightNumber, uint256 _departureTime) {
        string memory _flightDate = AirlineLibraries.parseTimestamp(_departureTime);
        require (allFlightDetailsMap[_flightNumber][_flightDate].flightNumber != _flightNumber, "Flight already present.");
        _;
    }

    modifier validateTimings(uint256 _departureTime, uint256 _arrivalTime) {
        require (_arrivalTime > _departureTime, "Invalid arrival & departure time.");
        require (block.timestamp < _departureTime, "Pleae use the future date.");
        _;
    }

    modifier validateFlightDateAndDepartureTime(string memory _flightDate, uint256 _departureTime) {
        require (AirlineLibraries.compareStrings(_flightDate, AirlineLibraries.parseTimestamp(_departureTime)), "Departure time must be on the flight date.");
        _;
    }
    
    modifier validateFlightStatus(uint _flightNumber, string memory _flightDate, FlightStatus status){
        require (allFlightDetailsMap[_flightNumber][_flightDate].flightStatus != status, "Flight Status is already updated.");
        require (allFlightDetailsMap[_flightNumber][_flightDate].flightStatus < status, "Flight Status is not modifiable to previous state.");
        _;
    }
    
    modifier flightNotCancelled(uint _flightNumber, string memory _flightDate){
        require (allFlightDetailsMap[_flightNumber][_flightDate].flightStatus != FlightStatus.CANCELLED, "Can't change status, as current status is cancelled.");
        _;
    }
    
    modifier flightNotArrived(uint _flightNumber, string memory _flightDate){
        require (allFlightDetailsMap[_flightNumber][_flightDate].flightStatus != FlightStatus.ARRIVED, "Can't change status, as current status is arrived.");
        _;
    }
    
    modifier flightNotDeparted(uint _flightNumber, string memory _flightDate){
        require (allFlightDetailsMap[_flightNumber][_flightDate].flightStatus != FlightStatus.DEPARTED, "Can't change status, as current status is departed.");
        _;
    }
    // Modifiers - END

    //constructor function
    constructor (string memory _airlineName, string memory _airlineSymbol, address _airlineAccount) {
        airlineName = _airlineName;
        airlineSymbol = _airlineSymbol;
        airlineBalance = 0;
        totalPenaltyAmount = 0;
        airlineAdmin = payable(msg.sender);
        airlineAccount = _airlineAccount;
        __setAirlineAdmin(msg.sender);
        __setAirlineAccounts(_airlineAccount);
        emit AirlineCreated(_airlineName, _airlineSymbol);
    }

    // Contract Accessors Operations - START
    function __setAirlineAdmin(address admin) private nonZeroAddress(admin) {
        airlineAdmin = payable(admin);
    }

    function modifyAirlineAdmin(address newAdmin) public onlyAirlineAdmin nonZeroAddress(newAdmin) {
         airlineAdmin = payable(newAdmin);
    }

    function __setAirlineAccounts(address _airlineAccount) private
    onlyAirlineAdmin nonZeroAddress(_airlineAccount){
        airlineAccount = _airlineAccount;
    }

    function modifyAirlineAccount(address _airlineAccount) public onlyAirlineAdmin nonZeroAddress(_airlineAccount) {
        if (airlineAccount != _airlineAccount) {
            airlineAccount = _airlineAccount;
        }
        else {
            emit Error("The new address entered is same as the existing address.");
        }
     }
    // Contract Accessors Operations - END

    // New Flight Set-Up - START
    function setupFlight(uint _flightNumber, string memory _source, string memory _destination,
    uint _fixedBasePrice, uint256 _departureTime, uint256 _arrivalTime,
    bool _activeStatus) public onlyAirline validateTimings(_departureTime, _arrivalTime) newFlightAvailability(_flightNumber, _departureTime){
        string memory _flightDate = AirlineLibraries.parseTimestamp(_departureTime);
        if (!(allFlightDetailsMap[_flightNumber][_flightDate].flightNumber == _flightNumber)) {
            __setupFlight(_flightNumber, _source, _destination, _fixedBasePrice, _departureTime, _arrivalTime, _flightDate, _activeStatus);
            emit FlightCreated(_flightNumber, msg.sender);
        }
        else {
            emit Error ("Flight already present. Please call modifyFlight() for modifications.");
        }
    }
    // New Flight Set-Up - END

    // Adding value to the map
    function __setupFlight(uint _flightNumber, string memory _source, string memory _destination,
    uint _fixedBasePrice, uint256 _departureTime, uint256 _arrivalTime,
    string memory _flightDate, bool _activeStatus) private {
        flightData storage flight = allFlightDetailsMap[_flightNumber][_flightDate];
        flight.flightNumber = _flightNumber;
        flight.source = _source;
        flight.destination = _destination;
        flight.fixedBasePrice = _fixedBasePrice;
        flight.departureTime = _departureTime;
        flight.arrivalTime = _arrivalTime;
        flight.flightDate = _flightDate;
        flight.duration = _arrivalTime - _departureTime;
        if (flight.duration < 14400) {
            flight.totalSeats = 170;
            flight.aircraft = Aircraft.Airbus_320;
        }
        else {
            flight.totalSeats = 240;
            flight.aircraft = Aircraft.Boeing_787_Dreamliner;
        }
        flight.totalPassengers = 0;
        allFlights.push(_flightNumber);
        isFlightActive[_flightNumber] = _activeStatus;
    }

    // Enable flight
    function enableFlight(uint _flightNumber) public onlyAirline flightInactive(_flightNumber){
        isFlightActive[_flightNumber] = true;
    }

    //Disable flight
    function disableFlight(uint _flightNumber) public onlyAirline flightActive(_flightNumber) {
        isFlightActive[_flightNumber] = false;
    }

    // Modify Flight - START
    function modifyFlight(uint _flightNumber, string memory _source, string memory _destination,
    uint _fixedBasePrice, uint256 _departureTime, uint256 _arrivalTime, string memory _flightDate)
    public onlyAirline flightAvailability(_flightNumber, _flightDate) flightInactive(_flightNumber)
    validateFlightDateAndDepartureTime(_flightDate, _departureTime) validateTimings(_departureTime, _arrivalTime) {
        __modifyFlight(_flightNumber, _source, _destination, _fixedBasePrice, _departureTime, _arrivalTime, _flightDate);
        emit FlightModified(_flightNumber, msg.sender);
    }
    // Modify Flight - END

    // // Modifying values in the map
    function __modifyFlight(uint _flightNumber, string memory _source, string memory _destination,
    uint _fixedBasePrice, uint256 _departureTime, uint256 _arrivalTime, string memory _flightDate) private {
        flightData storage flight = allFlightDetailsMap[_flightNumber][_flightDate];
        if (AirlineLibraries.compareStrings(flight.source, _source)) {
            flight.source = _source;
        }
        if (AirlineLibraries.compareStrings(flight.destination, _destination)) {
            flight.destination = _destination;
        }
        if (flight.fixedBasePrice != _fixedBasePrice) {
            flight.fixedBasePrice = _fixedBasePrice;
        }
        if (flight.departureTime != _departureTime) {
            flight.departureTime = _departureTime;
        }
        if (flight.arrivalTime != _arrivalTime) {
            flight.arrivalTime = _arrivalTime;
        }
        if (flight.duration != _arrivalTime - _departureTime) {
            flight.duration = _arrivalTime - _departureTime;
            if (flight.duration < 14400) {
                flight.totalSeats = 170;
                flight.aircraft = Aircraft.Airbus_320;
            }
            else {
                flight.totalSeats = 240;
                flight.aircraft = Aircraft.Boeing_787_Dreamliner;
            }
        }
    }

    // Flight Status Operations - START
    // TO-DO: Need to implement the status logic like we cannot change status of a cacncelled flight to arrived.
    
    function __settleAllTicket(uint _flightNumber, string memory _flightDate) private onlyAirline {
        address[] memory ticketsToBeSetteled = allFlightDetailsMap[_flightNumber][_flightDate].allTicketsInTheFlight;
        for (uint i=0; i<ticketsToBeSetteled.length; i++){
            TMSTicket(ticketsToBeSetteled[i]).settleTicket();
        }
    }
    
    function updateStatus(uint _flightNumber, string calldata _flightDate, FlightStatus _flightStatus) public onlyAirline {
        allFlightDetailsMap[_flightNumber][_flightDate].flightStatus = _flightStatus;
        emit StatusUpdated(_flightNumber, _flightDate, _flightStatus, msg.sender);
    }

    function __updateStatus(uint _flightNumber, string memory _flightDate, FlightStatus _flightStatus) private onlyAirline {
        allFlightDetailsMap[_flightNumber][_flightDate].flightStatus = _flightStatus;
        emit StatusUpdated(_flightNumber, _flightDate, _flightStatus, msg.sender);
    }

    function flightOnTime(uint _flightNumber, string memory _flightDate) public
    validateFlightStatus(_flightNumber, _flightDate, FlightStatus.ONTIME){
        __updateStatus(_flightNumber, _flightDate, FlightStatus.ONTIME);
    }

    function flightDelayed(uint _flightNumber, string memory _flightDate) public 
    flightNotCancelled(_flightNumber, _flightDate) flightNotArrived(_flightNumber, _flightDate) 
    flightNotDeparted(_flightNumber, _flightDate) validateFlightStatus(_flightNumber, _flightDate, FlightStatus.DELAYED){
        __updateStatus(_flightNumber, _flightDate, FlightStatus.DELAYED);
    }
    
    function flightCancelled(uint _flightNumber, string memory _flightDate) public 
    flightNotArrived(_flightNumber, _flightDate) flightNotDeparted(_flightNumber, _flightDate) 
    validateFlightStatus(_flightNumber, _flightDate, FlightStatus.CANCELLED){
        __updateStatus(_flightNumber, _flightDate, FlightStatus.CANCELLED);
        __settleAllTicket(_flightNumber, _flightDate);
    }

    function flightDeparted(uint _flightNumber, string memory _flightDate) public 
    flightNotArrived(_flightNumber, _flightDate)
    validateFlightStatus(_flightNumber, _flightDate, FlightStatus.DEPARTED){
        __updateStatus(_flightNumber, _flightDate, FlightStatus.DEPARTED);
    }

    function flightArrived(uint _flightNumber, string memory _flightDate) public
    validateFlightStatus(_flightNumber, _flightDate, FlightStatus.ARRIVED){
        __updateStatus(_flightNumber, _flightDate, FlightStatus.ARRIVED);
        __settleAllTicket(_flightNumber, _flightDate);
    }
    // Flight Status Operations - END

    // Getter for Flight Status - START
    function getFlightStatus(uint _flightNumber, string calldata _flightDate) public view flightAvailability(_flightNumber, _flightDate) returns (FlightStatus){
        return allFlightDetailsMap[_flightNumber][_flightDate].flightStatus;
    }
    // Getter for Flight Status - END

    function getArrTime(uint _flightNumber, string calldata _flightDate) public view flightAvailability(_flightNumber, _flightDate) returns (uint) {
        return allFlightDetailsMap[_flightNumber][_flightDate].arrivalTime;
    }

    function viewContractsList(uint _flightNumber, string calldata _flightDate) public view onlyAirline flightAvailability(_flightNumber, _flightDate) returns (address[] memory){
        return allFlightDetailsMap[_flightNumber][_flightDate].allTicketsInTheFlight;
    }

    function viewAirlineBalance() public onlyAirline {
        emit FlightBalance(airlineBalance);
    }

    function viewPenaltyPaid() public onlyAirline {
        emit PenaltyPaid(totalPenaltyAmount);
    }

    function getSeatLeft(uint _flightNumber, string calldata _flightDate) public view flightAvailability(_flightNumber, _flightDate) returns (uint) {
        return allFlightDetailsMap[_flightNumber][_flightDate].totalSeats - allFlightDetailsMap[_flightNumber][_flightDate].totalPassengers;
    }

    function getTotalSeats(uint _flightNumber, string calldata _flightDate) public view flightAvailability(_flightNumber, _flightDate) returns (uint) {
        return allFlightDetailsMap[_flightNumber][_flightDate].totalSeats;
    }

    function getFixedBasePrice(uint _flightNumber, string calldata _flightDate) public view flightAvailability(_flightNumber, _flightDate) returns (uint) {
        return allFlightDetailsMap[_flightNumber][_flightDate].fixedBasePrice;
    }

    // Book Ticket: Function for reserving the seat in a flight.
    function completeReservation(uint _flightNumber, string calldata _flightDate) external returns (uint8 seatNo) {
        flightData storage flight = allFlightDetailsMap[_flightNumber][_flightDate];
        require(flight.ticketExists[msg.sender] == true, "Error: Ticket not associated with this flight");
        require(flight.totalPassengers < flight.totalSeats, "Error: No seats left!!");
        
        uint8 _seatNumber = 1;
        for(uint8 i = 1; i <= flight.totalSeats; i++) {
            if(flight.reservedSeats[i] == address(0)) {
                _seatNumber = i;
                break;
            }
        }
        
        flight.reservedSeats[_seatNumber] = msg.sender;
        flight.totalPassengers += 1;
        return _seatNumber;
    }

    function createTicket(uint _flightNumber, string calldata _flightDate, address _customerAddr) external returns (address) {
        flightData storage flight = allFlightDetailsMap[_flightNumber][_flightDate];
        require(flight.totalPassengers < flight.totalSeats, "Error: No seats available");
        
        TMSTicket ticket = new TMSTicket(airlineAccount, _customerAddr, _flightNumber, 0,
         flight.source, flight.destination, _flightDate, flight.departureTime, flight.arrivalTime, flight.fixedBasePrice);

        address ticketAddr = address(ticket);

        flight.allTicketsInTheFlight.push(ticketAddr);
        flight.ticketExists[ticketAddr] = true;
        
        emit TicketBooked(ticketAddr);
        return ticketAddr;
    }

    function cancelReservation(uint _flightNumber, string memory _flightDate, uint8 _seatNo) external {
        flightData storage flight = allFlightDetailsMap[_flightNumber][_flightDate];
        require(flight.ticketExists[msg.sender] == true, "Error: Ticket not associated with this flight");
        
        flight.reservedSeats[_seatNo] = address(0);
        
        flight.totalPassengers -= 1;
    }
    
    // Method for searching a flight between two destinations.
    function searchFlight(string calldata origin, string calldata dest, string calldata travelDate) public view returns (uint flightFound){
       for(uint i=0; i < allFlights.length ; i++){
        //get the address and send a value
            if (AirlineLibraries.compareStrings(allFlightDetailsMap[allFlights[i]][travelDate].source, origin) && 
                AirlineLibraries.compareStrings(allFlightDetailsMap[allFlights[i]][travelDate].destination, dest)){
                return allFlightDetailsMap[allFlights[i]][travelDate].flightNumber;
            }
        }
    }
}
