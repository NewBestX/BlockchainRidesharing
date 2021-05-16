// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./owner.sol";

contract Ridesharing is Owner {
    
    event NewRide(uint rideId, string startPlace, string destination, uint date, uint price, uint8 seats);
    event NewReservation(uint rideId, address reservationOwner, uint8 seats);
    event ReservationCancelled(uint rideId, address reservationOwner, uint8 seats);
    event RideFinished(uint rideId);
    event RideCancelled(uint rideId);
    event NewRating(uint rideId, address person, uint stars);
    
    struct Ride {
      string startPlace;
      string destination;
      uint date;
      uint price;
      uint8 seats;
      bool finished;
      bool cancelled;
    }
    
    struct Reservation {
      address owner;
      uint8 numSeats;
      bool rated;
    }
    
    Ride[] public rides;
    mapping (uint => address) public rideToOwner;
    mapping (uint => Reservation[]) public rideToReservations;
    mapping (address => uint8[]) public ownerToRatings;

    /// @notice Creates a new ride
    /// @param _startPlace starting place of the ride 
    /// @param _destination destination of the ride
    /// @param _date the starting date of the ride expressed in seconds since the epoch
    /// @param _price the fee for one seat in gwei
    /// @param _seats the number of available seats
    function createRide(string memory _startPlace, string memory _destination, uint _date, uint _price, uint8 _seats) external validRide(_date, _price, _seats) {
        rides.push(Ride(_startPlace, _destination, _date, _price, _seats, false, false));
        uint id = rides.length - 1;
        rideToOwner[id] = msg.sender;
        emit NewRide(id, _startPlace, _destination, _date, _price, _seats);
    }
    
    /// @notice Creates a new reservation on a given ride
    /// @param _rideId the ride to reserve seats on
    /// @param _numSeats the number of seats reserved
    function reserveSeat(uint _rideId, uint8 _numSeats) external payable {
        Ride memory ride = rides[_rideId];
        
        require(ride.finished == false);
        require(ride.cancelled == false);
        require(block.timestamp < ride.date);
        
        uint fee = ride.price * _numSeats;
        require(msg.value == fee * 1 gwei);
        
        uint availableSeats = ride.seats;
        Reservation[] storage resArray = rideToReservations[_rideId];
        uint reservedIndex = 0;
        bool hasReservation = false;
        for (uint i = 0; i < resArray.length; i++) {
            availableSeats = availableSeats - resArray[i].numSeats;
            if (resArray[i].owner == msg.sender) {
                reservedIndex = i;
                hasReservation = true;
            }
        }
        
        require(_numSeats <= availableSeats);
        
        if (!hasReservation) {
            resArray.push(Reservation(msg.sender, _numSeats, false));
        } else {
            resArray[reservedIndex].numSeats = resArray[reservedIndex].numSeats + _numSeats;
        }
        
        emit NewReservation(_rideId, msg.sender, _numSeats);
    }
    
    /// @notice Cancels a reservation on a given ride
    /// @param _rideId the ride to cancel the reservation on
    /// @param _numSeats the number of seats cancelled from the reservation
    function cancelReservation(uint _rideId, uint8 _numSeats) public {
        Ride memory ride = rides[_rideId];
        
        require(ride.finished == false);
        require(ride.cancelled == false);
        require(block.timestamp < ride.date);
        
        Reservation[] storage resArray = rideToReservations[_rideId];
        uint reservedIndex = 0;
        bool hasReservation = false;
        for (uint i = 0; i < resArray.length; i++) {
            if (resArray[i].owner == msg.sender) {
                reservedIndex = i;
                hasReservation = true;
            }
        }
        
        require(hasReservation);
        require(resArray[reservedIndex].numSeats >= _numSeats);
        
        resArray[reservedIndex].numSeats = resArray[reservedIndex].numSeats - _numSeats;
        
        uint fee = rides[_rideId].price * _numSeats;
        payable(msg.sender).transfer(fee * 1 gwei);
        
        emit ReservationCancelled(_rideId, msg.sender, _numSeats);
    }
    
    /// @notice Called by the owner when a ride is finished to receive payment for the reserved seats
    /// @param _rideId the id of the finished ride
    function finishRide(uint _rideId) external {
        require(rideToOwner[_rideId] == msg.sender);
        Ride storage ride = rides[_rideId];
        
        require(ride.finished == false);
        require(ride.cancelled == false);
        require(block.timestamp > ride.date);
        ride.finished = true;

        Reservation[] memory resArray = rideToReservations[_rideId];
        uint seatCount = 0;
        for (uint i = 0; i < resArray.length; i++) {
            seatCount = seatCount + resArray[i].numSeats;
        }
        
        uint fee = ride.price * seatCount;
        payable(msg.sender).transfer(fee * 1 gwei);
        
        emit RideFinished(_rideId);
    }
    
    /// @notice Called when a ride is cancelled before it begins
    /// @param _rideId the ride to be cancelled
    function cancelRide(uint _rideId) external {
        require(rideToOwner[_rideId] == msg.sender);
        Ride storage ride = rides[_rideId];
        
        require(ride.finished == false);
        require(ride.cancelled == false);
        require(block.timestamp < ride.date);
        ride.cancelled = true;
        
        Reservation[] memory resArray = rideToReservations[_rideId];
        for (uint i = 0; i < resArray.length; i++) {
            uint fee = ride.price * resArray[i].numSeats;
            payable(resArray[i].owner).transfer(fee * 1 gwei);
        }
        
        emit RideCancelled(_rideId);
    }
    
    /// @notice Gives a rating to the owner of a ride
    /// @param _rideId the ride to be rated
    /// @param _stars the rating, from 1 to 5
    function giveRating(uint _rideId, uint8 _stars) external {
        Ride memory ride = rides[_rideId];
        
        require(ride.finished == true);
        require(_stars <= 5 && _stars > 0);
        
        Reservation[] storage resArray = rideToReservations[_rideId];
        uint reservedIndex = 0;
        bool hasUnratedReservation = false;
        for (uint i = 0; i < resArray.length; i++) {
            if (resArray[i].owner == msg.sender && resArray[i].rated == false) {
                reservedIndex = i;
                hasUnratedReservation = true;
            }
        }
        
        require(hasUnratedReservation == true);
        resArray[reservedIndex].rated = true;
        
        uint8[] storage ownerRatings = ownerToRatings[rideToOwner[_rideId]];
        ownerRatings.push(_stars);
        
        emit NewRating(_rideId, msg.sender, _stars);
    }
    
    /// @notice Gets the average rating of a user
    /// @param _owner address of the user
    /// @return the rating average, multiplied by 100
    function getRating(address _owner) external view returns(uint) {
        uint8[] memory ownerRatings = ownerToRatings[_owner];
        
        uint sum = 0;
        for (uint i = 0; i < ownerRatings.length; i++) {
            sum = sum + (uint(ownerRatings[i]) * 100);
        }
        
        return sum / ownerRatings.length;
    }
    
    /// @notice Gets all the created rides
    /// @return list of rides
    function getAllRides() external view returns(Ride[] memory) {
        return rides;
    }
    
    modifier validRide(uint _date, uint _price, uint32 _seats) {
        require(_date > block.timestamp);
        require(_price > 0);
        require(_seats > 0);
        _;
    }
    
}
