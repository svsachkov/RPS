// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RPC {
    using SafeMath for uint256;

    enum Stage { None, Join, Reveal, Finished }
    enum Pick { None, Rock, Paper, Scissors }
    enum Result { Draw, Win, Lose }

    struct PlayerPick {
        bytes32 encrypted;

        uint256 revealDeadline;

        bytes32 blindingFactor;
        Pick decrypted;
    }

    struct Player {
        address payable player;
        uint256 deposit;

        PlayerPick pick;
    }

    struct Game {
        Stage stage;
        uint256 joinDeadline;

        Player player1; // creator
        Player player2; // joiner
    }


    uint256 gameCount;
    mapping(uint256 => Game) games;

    uint256 revealTimeout = 1 days;
    uint256 joinTimeout = 1 days;

    address payable anybody = payable(address(0));

    constructor(uint256 _revealTimeout, uint256 _joinTimeout) {
        revealTimeout = _revealTimeout;
        joinTimeout = _joinTimeout;
    }

    modifier stageEqual(uint256 gameId, Stage stage) {
        require(games[gameId].stage == stage, "incorrect game stage for calling this method");
        _;
    }

    modifier isPlayerOf(uint256 gameId) {
        Game storage game = games[gameId];
        require(msg.sender == game.player1.player || msg.sender == game.player2.player, "only game participant can call this method. View game info");
        _;
    }

    modifier mayJoinAsOpponent(uint256 gameId) {
        Game storage game = games[gameId];
        require(
            game.player2.player == anybody || // public game
            game.player2.player == msg.sender, // private game
            "cannot join private game"
        );
        _;
    }

    function createPrivate(bytes32 encryptedPick, address payable opponent) public payable returns(uint256) {
        return createGame(encryptedPick, opponent);
    }

    function createPublic(bytes32 encryptedPick) public payable returns(uint256) {
        return createGame(encryptedPick, anybody);
    }

    function createGame(bytes32 encryptedPick, address payable opponent) private returns(uint256) {
        require(msg.value > 0, "cannot create games with non-positive deposits. Provide msg.value");

        gameCount += 1;

        Game storage game = games[gameCount];
        game.stage = Stage.Join;
        game.joinDeadline = block.timestamp.add(joinTimeout);

        Player storage player = game.player1;
        player.player = payable(msg.sender);
        player.deposit = msg.value;
        player.pick.encrypted = encryptedPick;
        player.pick.revealDeadline = block.timestamp.add(revealTimeout);

        game.player2.player = opponent;

        return gameCount;
    }

    function cancelGame(uint256 gameId) public
        stageEqual(gameId, Stage.Join) {

        Game storage game = games[gameId];
        Player storage creator = game.player1;

        require(creator.player == msg.sender, "only game creator can cancel game");

        creator.player.transfer(creator.deposit);
        creator.deposit = 0;

        game.stage = Stage.Finished;
    }

    function joinGame(uint256 gameId, bytes32 encryptedPick) public payable
        stageEqual(gameId, Stage.Join)
        mayJoinAsOpponent(gameId) {

        Game storage game = games[gameId];

        require(checkDeadline(game.joinDeadline), "cannot join after join deadline");
        require(msg.value == game.player1.deposit, "Incorrect msg value. View this game toBet info");

        Player storage player = game.player2;

        player.player = payable(msg.sender);
        player.deposit = msg.value; // same as game.player1.deposit
        player.pick.encrypted = encryptedPick;
        player.pick.revealDeadline = block.timestamp.add(revealTimeout);

        game.stage = Stage.Reveal;
    }

    function revealPick(uint256 gameId, uint256 pick, bytes32 blindingFactor) public
        stageEqual(gameId, Stage.Reveal)
        isPlayerOf(gameId) {

        Game storage game = games[gameId];

        Player storage player = getPlayer(game, msg.sender);

        require(checkDeadline(player.pick.revealDeadline),
            "cannot reveal after reveal deadline");
        require(player.pick.blindingFactor == 0,
            "cannot reveal twice");
        require(player.pick.encrypted == keccak256(abi.encodePacked(pick, blindingFactor)),
            "incorrect pick or blindingFactor");

        player.pick.blindingFactor = blindingFactor;
        player.pick.decrypted = mapUintToPick(pick);

        Player storage opponent = getOpponentPlayer(game, msg.sender);

        if (opponent.pick.decrypted == Pick.None) {
            return; // wait for him
        }

        game.stage = Stage.Finished;

        Result result = resolveResult(player.pick.decrypted, opponent.pick.decrypted);

        if (result == Result.Lose) {
            opponent.deposit += player.deposit;
            player.deposit = 0;
        }
        if (result == Result.Win) {
            player.deposit += opponent.deposit;
            opponent.deposit = 0;
        }
        // else Result.Draw => deposits already correct
    }

    function withdraw(uint256 gameId) public
        stageEqual(gameId, Stage.Finished)
        isPlayerOf(gameId) {

        Game storage game = games[gameId];

        Player storage player = getPlayer(game, msg.sender);

        if (player.deposit == 0) {
            revert("nothing to withdraw");
        }

        player.player.transfer(player.deposit);
        player.deposit = 0;
    }

    function withdrawByAutoWin(uint256 gameId) public
        stageEqual(gameId, Stage.Reveal)
        isPlayerOf(gameId) {

        Game storage game = games[gameId];

        Player storage player = getPlayer(game, msg.sender);
        Player storage opponent = getOpponentPlayer(game, msg.sender);

        require(player.pick.decrypted != Pick.None,
            "cannot auto-win without self reveal");
        require(opponent.pick.decrypted == Pick.None,
            "cannot auto-win. Opponent has done reveal");

        if (checkDeadline(opponent.pick.revealDeadline)) {
            revert("opponent's reveal deadline has not passed yet. He can still reveal and win");
        }

        uint256 toTransfer = player.deposit + opponent.deposit;
        player.deposit = 0;
        opponent.deposit = 0;

        player.player.transfer(toTransfer);

        game.stage = Stage.Finished;
    }

    function getGameInfo(uint256 gameId) public view returns(Game memory) {
        return games[gameId];
    }

    function checkDeadline(uint256 deadline) private view returns(bool) {
        return block.timestamp < deadline;
    }

    function getPlayer(Game storage game, address player) private view returns(Player storage) {
        if (game.player1.player == player) {
            return game.player1;
        }
        if (game.player2.player == player) {
            return game.player2;
        }
        revert();
    }

    function getOpponentPlayer(Game storage game, address player)  private view returns(Player storage) {
        if (game.player1.player == player) {
            return game.player1;
        }
        if (game.player2.player == player) {
            return game.player1;
        }
        revert();
    }

    function mapUintToPick(uint256 value) private pure returns (Pick) {
        Pick pick = Pick(value);
        require(pick == Pick.Rock || pick == Pick.Paper || pick == Pick.Scissors, "invalid value");

        return pick;
    }

    function resolveResult(Pick me, Pick other) private pure returns(Result) {
        if (
            (me == Pick.Paper && other == Pick.Rock) ||
            (me == Pick.Rock && other == Pick.Scissors) ||
            (me == Pick.Scissors && other == Pick.Paper)
        ) {
            return Result.Win;
        }
        if (
            (me == Pick.Paper && other == Pick.Scissors) ||
            (me == Pick.Rock && other == Pick.Paper) ||
            (me == Pick.Scissors && other == Pick.Rock)
        ) {
            return Result.Lose;
        }
        return Result.Draw;
    }
}
