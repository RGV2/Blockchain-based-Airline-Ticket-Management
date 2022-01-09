// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./TMSAirline.sol";

contract TMSTicket {
    event TicketConfirmed(uint fareAmount, address ticketAddr);
    event TicketCancelled(address ticketAddr);
    event TicketSettled(address ticketAddr);
    event TicketRequested(
        uint _flightNo, uint8 _seatNo, 
        string _source, string _destination, string _journeyDate, 
        uint schedDep, uint schedArr
    );
    
    // Different stages of lifetime of a ticket
    enum TicketStatus {CREATED, CONFIRMED, CANCELLED, SETTLED}
    
    // Unique ID for this ticket(address of this contract)
    address private _ticketID;

    // Addresses involved in the contract
    address private _airlineContract; // creator of this contract
    address payable private _airlineAccount;
    address payable private _customerAccount;
    TMSAirline private _airline;
    
    // Stores fare details
    uint private _baseFare;
    uint private _totalFare;
    bool private _isFarePaid;

    // Stores creation time of this contract
    uint private _createTime;

    // Stores current ticket status
    TicketStatus private _ticketStatus;
    
    struct TravelDetails {
        uint flightNumber;
        uint8 seatNumber;
        string source;
        string destination;
        string journeyDate;
        uint schedDep;
        uint schedArr;
    }

    // Stores details of the trip
    TravelDetails private _travelDetails;
    
    constructor(
            address airlineAccount_,
            address customerAccount_,
            uint flightNumber_,
            uint8 seatNumber_,
            string memory source_,
            string memory destination_,
            string memory journeyDate_,
            uint depTime,
            uint arrTime,
            uint baseFare_
        ) nonZeroAddress(customerAccount_) nonZeroAddress(airlineAccount_) {
        _ticketID = address(this);
        _airlineContract = msg.sender;
        _airlineAccount = payable(airlineAccount_);
        _customerAccount = payable(customerAccount_);
        _ticketStatus = TicketStatus.CREATED;
        
        _travelDetails = TravelDetails(
            {
                flightNumber: flightNumber_,
                seatNumber: seatNumber_,
                source: source_,
                destination: destination_,
                journeyDate: journeyDate_,
                schedDep: depTime,
                schedArr: arrTime
            }
        );
        
        _baseFare = baseFare_;
        _totalFare = baseFare_;
        _isFarePaid = false;
        _airline = TMSAirline(_airlineContract);
        _createTime = block.timestamp;
    }

    modifier nonZeroAddress(address addr) {
        require(addr != address(0), "Error: Address cannot be 0");
        _;
    }
    
    modifier onlyCustomer {
        require(msg.sender == _customerAccount, "Error: Only customer can do this action");
        _;
    }
    
    modifier onlyAirline {
        require(msg.sender == _airlineAccount, "Error: Only airline can do this action");
        _;
    }

    modifier onlyCustomerOrAirline {
        require((msg.sender == _airlineAccount) || (msg.sender == _customerAccount), "Error: Only customer or airline can do this action");
        _;
    }
    
    function getTravelDetails() public onlyCustomerOrAirline {
        emit TicketRequested(
            _travelDetails.flightNumber,
            _travelDetails.seatNumber,
            _travelDetails.source,
            _travelDetails.destination,
            _travelDetails.journeyDate,
            _travelDetails.schedDep,
            _travelDetails.schedArr
        );
    }
    
    
    function payFare() public payable onlyCustomer {
        require(_ticketStatus == TicketStatus.CREATED, "Error: Fare already paid or ticket is settled");
        _totalFare = _calculateFare(); // calculate the fare & save it in the contract

        require(msg.value == _totalFare, "Error: Invalid amount");

        _travelDetails.seatNumber = _airline.completeReservation(_travelDetails.flightNumber, _travelDetails.journeyDate);
        
        _ticketStatus = TicketStatus.CONFIRMED;
        _isFarePaid = true;
        emit TicketConfirmed(_totalFare, _ticketID);
    }
    
    function cancelTicket() public payable onlyCustomer {
        require(_ticketStatus == TicketStatus.CONFIRMED, "Error: Ticket is already cancelled or settled");

        TMSAirline.FlightStatus flightStatus = _airline.getFlightStatus(_travelDetails.flightNumber, _travelDetails.journeyDate);
        if(flightStatus == TMSAirline.FlightStatus.ARRIVED || flightStatus == TMSAirline.FlightStatus.DEPARTED) {
            revert("Error: Cannot cancel after departure or arrival");
        }

        uint schedDep = _travelDetails.schedDep;
        
        if(schedDep - (2* 1 hours) < block.timestamp) {
            revert("Error: Cannot cancel within two hours of departure");
        }
        
        uint penalty = _calcCancelPenalty();
        _customerAccount.transfer(_totalFare - penalty);
        _airlineAccount.transfer(penalty);
        _ticketStatus = TicketStatus.CANCELLED;
        
        _airline.cancelReservation(_travelDetails.flightNumber, _travelDetails.journeyDate, _travelDetails.seatNumber);
        emit TicketCancelled(_ticketID);
    }
    
    function claimRefund() public payable onlyCustomer {
        require(_ticketStatus != TicketStatus.SETTLED && _ticketStatus != TicketStatus.CANCELLED,
        "Error: This ticket has already been settled");

        uint schedArr = _travelDetails.schedArr;
        
        if(schedArr + (24 * 1 hours) > block.timestamp) {
            revert("Error: Cannot settle before 24 hours past scheduled arrival");
        }

        TMSAirline.FlightStatus flightStatus = _airline.getFlightStatus(_travelDetails.flightNumber, _travelDetails.journeyDate);
        if(flightStatus != TMSAirline.FlightStatus.ARRIVED) {
            _customerAccount.transfer(_totalFare);
            _ticketStatus = TicketStatus.SETTLED;
            emit TicketSettled(_ticketID);
        }

        uint penalty = _calcDelayPenalty();

        _customerAccount.transfer(_totalFare - penalty);
        _airlineAccount.transfer(penalty);
        _ticketStatus = TicketStatus.SETTLED;
        emit TicketSettled(_ticketID);
    }

    function getTotalFare() public view returns (uint) {
        return _calculateFare();
    }
    
    function settleTicket() external payable {
        require(msg.sender == _airlineContract, "Error: Only Airline can do this.");
        
        require(_ticketStatus != TicketStatus.SETTLED && _ticketStatus != TicketStatus.CANCELLED, 
        "Error: This ticket has already been settled");
        

        uint schedArr = _travelDetails.schedArr;
        if(schedArr > block.timestamp) {
            revert("Error: Cannot settle before scheduled arrival");
        }

        TMSAirline.FlightStatus flightStatus = _airline.getFlightStatus(_travelDetails.flightNumber, _travelDetails.journeyDate);
        if(flightStatus == TMSAirline.FlightStatus.CANCELLED) {
            _customerAccount.transfer(_totalFare);
            _ticketStatus = TicketStatus.SETTLED;
            emit TicketSettled(_ticketID);
        }

        if(flightStatus != TMSAirline.FlightStatus.ARRIVED) {
            revert("Error: Flight has not arrived yet");
        }

        uint delayPenalty = _calcDelayPenalty();
        if(delayPenalty == 0) {
            _airlineAccount.transfer(_totalFare);
        } else {
            _airlineAccount.transfer(_totalFare-delayPenalty);
            _customerAccount.transfer(delayPenalty);
        }

        _ticketStatus = TicketStatus.SETTLED;
        emit TicketSettled(_ticketID);
    }
    
    function _calculateFare() private view returns (uint) {
        uint8 dynamicFarePercent = _calculateDynamicFarePercent();
        uint dynamicFare = (_baseFare*dynamicFarePercent) / 100;

        return _baseFare + dynamicFare;
    }

    function _calculateDynamicFarePercent() private view returns (uint8) {
        uint availableSeats = _airline.getSeatLeft(_travelDetails.flightNumber, _travelDetails.journeyDate);
        uint totalSeats = _airline.getTotalSeats(_travelDetails.flightNumber, _travelDetails.journeyDate);

        require(availableSeats != 0, "Error: No seats left");

        uint availableSeatsPercent = (availableSeats*100) / totalSeats;
        
        uint8 farePercent = 0;
        if(availableSeatsPercent >= 50) {
            farePercent = 0;
        } else if(availableSeatsPercent >= 25) {
            farePercent = 50;
        } else {
            farePercent = 100;
        }

        return farePercent;
    }

    function _calcDelayPenalty() private view returns (uint) {
        uint8 penaltyPercent = _calcDelayPenaltyPercent();
        uint penaltyAmount = (_totalFare * penaltyPercent) / 100;

        return penaltyAmount;
    }

    function _calcDelayPenaltyPercent() private view returns (uint8) {
        uint actArr = _airline.getArrTime(_travelDetails.flightNumber, _travelDetails.journeyDate);
        uint schedArr = _travelDetails.schedArr;
        
        uint8 penaltyPercent = 0;
        if(actArr-schedArr < 30*1 minutes) {
            penaltyPercent = 0;
        } else if(actArr-schedArr < 2*1 hours) {
            penaltyPercent = 10;
        } else {
            penaltyPercent = 30;
        }

        return penaltyPercent;
    }

    function _calcCancelPenalty() private view returns (uint) {
        uint8 penaltyPercent = _calcCancelPenaltyPercent();
        uint penaltyAmount = (_totalFare * penaltyPercent) / 100;

        return penaltyAmount;
    }

    function _calcCancelPenaltyPercent() private view returns (uint8) {
        uint currentTime = block.timestamp;
        uint timeLeft = _travelDetails.schedDep - currentTime;
        uint8 penaltyPercent = 0;
        
        if(timeLeft <=  2 * 1 hours) {
            penaltyPercent = 100;
        } else if (timeLeft <= 3 * 1 days) {
            penaltyPercent = 50;
        } else {
            penaltyPercent = 10;
        }
        
        return penaltyPercent;
    }
}
