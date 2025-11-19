import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Nat "mo:base/Nat";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Float "mo:base/Float";
import Array "mo:base/Array";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Iter "mo:base/Iter";

persistent actor Dbank {
  // -----------------------------
  // Constants and Configuration
  // -----------------------------
  transient let INTEREST_RATE : Float = 0.05;
  transient let STAKING_REWARD_RATE : Float = 0.08;
  transient let LOAN_INTEREST_RATE : Float = 0.12;
  transient let MIN_STAKING_AMOUNT : Nat = 1000;
  transient let MIN_LOAN_AMOUNT : Nat = 500;
  transient let MAX_LOAN_TO_STAKING_RATIO : Float = 0.7;

  // -----------------------------
  // Types and Records
  // -----------------------------
  public type OperationResult = Result.Result<Nat, Text>;
  
  public type AccountInfo = {
    id : Text;
    balance : Nat;
    stakedAmount : Nat;
    totalEarnedStaking : Nat;
    totalLoaned : Nat;
    loanCount : Nat;
    lastInterestApplied : Int;
    transactionCount : Nat;
    isActive : Bool;
  };

  public type StakingInfo = {
    amount : Nat;
    startTime : Int;
    rewardRate : Float;
    isActive : Bool;
  };

  public type LoanInfo = {
    amount : Nat;
    principal : Nat;
    interestRate : Float;
    startTime : Int;
    dueDate : Int;
    collateralAmount : Nat;
    status : LoanStatus;
  };

  public type LoanStatus = {
    #active;
    #completed;
    #defaulted;
  };

  public type Transaction = {
    id : Nat;
    txType : Text;
    amount : Nat;
    timestamp : Int;
    description : Text;
  };

  public type SystemStats = {
    totalStaked : Nat;
    totalLoans : Nat;
    totalUsers : Nat;
    totalValueLocked : Nat;
    activeLoans : Nat;
    activeStakers : Nat;
  };

  // -----------------------------
  // Storage using stable arrays
  // -----------------------------
  stable var accountData : [(Text, AccountInfo)] = [];
  stable var stakingData : [(Text, StakingInfo)] = [];
  stable var loanData : [(Text, [LoanInfo])] = [];
  stable var transactionData : [(Text, [Transaction])] = [];
  
  // Memory caches (not persistent)
  transient var accounts = HashMap.HashMap<Text, AccountInfo>(10, Text.equal, Text.hash);
  transient var stakingRecords = HashMap.HashMap<Text, StakingInfo>(10, Text.equal, Text.hash);
  transient var loanRecords = HashMap.HashMap<Text, [LoanInfo]>(10, Text.equal, Text.hash);
  transient var transactions = HashMap.HashMap<Text, [Transaction]>(10, Text.equal, Text.hash);
  
  // System stats
  transient var systemStats : SystemStats = {
    totalStaked = 0;
    totalLoans = 0;
    totalUsers = 0;
    totalValueLocked = 0;
    activeLoans = 0;
    activeStakers = 0;
  };

  // ID counters
  transient var accountCounter : Nat = 0;
  transient var loanCounter : Nat = 0;
  transient var transactionCounter : Nat = 0;

  // -----------------------------
  // Upgrade and initialization
  // -----------------------------
  system func preupgrade() {
    accountData := Array.map<(Text, AccountInfo), (Text, AccountInfo)>(
      Iter.toArray(accounts.entries()),
      func(x) { x }
    );
    stakingData := Array.map<(Text, StakingInfo), (Text, StakingInfo)>(
      Iter.toArray(stakingRecords.entries()),
      func(x) { x }
    );
    loanData := Array.map<(Text, [LoanInfo]), (Text, [LoanInfo])>(
      Iter.toArray(loanRecords.entries()),
      func(x) { x }
    );
    transactionData := Array.map<(Text, [Transaction]), (Text, [Transaction])>(
      Iter.toArray(transactions.entries()),
      func(x) { x }
    );
  };

  system func postupgrade() {
    accounts := HashMap.HashMap<Text, AccountInfo>(10, Text.equal, Text.hash);
    stakingRecords := HashMap.HashMap<Text, StakingInfo>(10, Text.equal, Text.hash);
    loanRecords := HashMap.HashMap<Text, [LoanInfo]>(10, Text.equal, Text.hash);
    transactions := HashMap.HashMap<Text, [Transaction]>(10, Text.equal, Text.hash);
    
    for ((key, value) in accountData.vals()) {
      accounts.put(key, value);
    };
    for ((key, value) in stakingData.vals()) {
      stakingRecords.put(key, value);
    };
    for ((key, value) in loanData.vals()) {
      loanRecords.put(key, value);
    };
    for ((key, value) in transactionData.vals()) {
      transactions.put(key, value);
    };
    
    accountData := [];
    stakingData := [];
    loanData := [];
    transactionData := [];
  };

  // -----------------------------
  // Utility Functions
  // -----------------------------

  // Helper function to get caller principal as a string (using a simple approach)
  private func getCallerPrincipal() : Text {
    // For development, use a simple identifier
    // In production, this would use proper principal handling
    "user-" # Nat.toText(123456);
  };

  private func createAccount(principal : Text) : AccountInfo {
    accountCounter += 1;
    let newAccount : AccountInfo = {
      id = principal;
      balance = 0;
      stakedAmount = 0;
      totalEarnedStaking = 0;
      totalLoaned = 0;
      loanCount = 0;
      lastInterestApplied = Time.now();
      transactionCount = 0;
      isActive = true;
    };
    accounts.put(principal, newAccount);
    updateSystemStats();
    newAccount;
  };

  private func getAccount(principal : Text) : AccountInfo {
    switch (accounts.get(principal)) {
      case null { createAccount(principal) };
      case (?account) { account };
    };
  };

  private func updateAccount(principal : Text, newAccount : AccountInfo) {
    accounts.put(principal, newAccount);
  };

  private func addTransaction(principal : Text, tType : Text, amount : Nat, description : Text) {
    let newTransaction : Transaction = {
      id = transactionCounter;
      txType = tType;
      amount = amount;
      timestamp = Time.now();
      description = description;
    };
    transactionCounter += 1;
    
    let existingTransactions = switch (transactions.get(principal)) {
      case null { [] };
      case (?txs) { txs };
    };
    transactions.put(principal, Array.append(existingTransactions, [newTransaction]));
  };

  private func updateSystemStats() {
    let accountEntries = Iter.toArray(accounts.entries());
    let totalUsers = accountEntries.size();
    let totalStaked = Array.foldLeft<(Text, AccountInfo), Nat>(
      accountEntries, 
      0, 
      func(acc, entry) { acc + entry.1.stakedAmount }
    );
    let totalLoans = Array.foldLeft<(Text, AccountInfo), Nat>(
      accountEntries, 
      0, 
      func(acc, entry) { acc + entry.1.totalLoaned }
    );
    
    systemStats := {
      totalStaked = totalStaked;
      totalLoans = totalLoans;
      totalUsers = totalUsers;
      totalValueLocked = totalStaked;
      activeLoans = totalLoans; // Simplified for now
      activeStakers = Iter.toArray(stakingRecords.entries()).size();
    };
  };

  private func applyInterest(account : AccountInfo) : AccountInfo {
    let now = Time.now();
    let elapsedSeconds = (now - account.lastInterestApplied) / 1_000_000_000;
    let interestPeriodSeconds = 60 * 60 * 24; // Daily interest
    let periods = Float.fromInt(elapsedSeconds) / Float.fromInt(interestPeriodSeconds);
    
    if (periods > 0.0 and account.balance > 0) {
      let multiplier = Float.pow(1.0 + INTEREST_RATE, periods);
      let newBalance = Int.abs(Float.toInt(Float.fromInt(account.balance) * multiplier));
      {
        account with
        balance = newBalance;
        lastInterestApplied = now;
      };
    } else {
      account;
    };
  };

  private func applyStakingRewards(principal : Text, stakingInfo : StakingInfo) : StakingInfo {
    if (not stakingInfo.isActive) { return stakingInfo; };
    
    let now = Time.now();
    let elapsedSeconds = (now - stakingInfo.startTime) / 1_000_000_000;
    let rewardPeriodSeconds = 60 * 60 * 24; // Daily compounding
    let periods = Float.fromInt(elapsedSeconds) / Float.fromInt(rewardPeriodSeconds);
    
    if (periods > 0.0) {
      let multiplier = Float.pow(1.0 + STAKING_REWARD_RATE, periods);
      let newAmount = Int.abs(Float.toInt(Float.fromInt(stakingInfo.amount) * multiplier));
      {
        stakingInfo with
        amount = newAmount;
      };
    } else {
      stakingInfo;
    };
  };

  private func updateLoanInArray(loans : [LoanInfo], index : Nat, newLoan : LoanInfo) : [LoanInfo] {
    if (index >= loans.size()) { return loans; };
    var result : [LoanInfo] = [];
    var i : Nat = 0;
    while (i < loans.size()) {
      if (i == index) {
        result := Array.append(result, [newLoan]);
      } else {
        result := Array.append(result, [loans[i]]);
      };
      i += 1;
    };
    result;
  };

  // -----------------------------
  // Public Methods
  // -----------------------------

  // Get account balance
  public func getBalance() : async Nat {
    let principal = getCallerPrincipal();
    var account = getAccount(principal);
    account := applyInterest(account);
    updateAccount(principal, account);
    account.balance;
  };

  // Deposit money
  public func topUp(amount : Nat) : async OperationResult {
    if (amount == 0) return #err("Amount must be greater than 0");
    
    let principal = getCallerPrincipal();
    var account = getAccount(principal);
    account := applyInterest(account);
    
    account := {
      account with
      balance = account.balance + amount
    };
    updateAccount(principal, account);
    addTransaction(principal, "Deposit", amount, "Account top-up");
    
    #ok(account.balance);
  };

  // Withdraw money
  public func withdraw(amount : Nat) : async OperationResult {
    if (amount == 0) return #err("Amount must be greater than 0");
    
    let principal = getCallerPrincipal();
    var account = getAccount(principal);
    account := applyInterest(account);
    
    if (amount > account.balance) return #err("Insufficient funds");
    
    account := {
      account with
      balance = account.balance - amount
    };
    updateAccount(principal, account);
    addTransaction(principal, "Withdrawal", amount, "Account withdrawal");
    
    #ok(account.balance);
  };

  // -----------------------------
  // Staking Functions
  // -----------------------------

  // Start staking
  public func stakeTokens(amount : Nat) : async OperationResult {
    if (amount < MIN_STAKING_AMOUNT) return #err("Minimum staking amount is " # Nat.toText(MIN_STAKING_AMOUNT));
    
    let principal = getCallerPrincipal();
    var account = getAccount(principal);
    account := applyInterest(account);
    
    if (amount > account.balance) return #err("Insufficient balance for staking");
    
    // Create staking record
    let stakingInfo : StakingInfo = {
      amount = amount;
      startTime = Time.now();
      rewardRate = STAKING_REWARD_RATE;
      isActive = true;
    };
    stakingRecords.put(principal, stakingInfo);
    
    // Update account
    account := {
      account with
      balance = account.balance - amount;
      stakedAmount = account.stakedAmount + amount
    };
    updateAccount(principal, account);
    addTransaction(principal, "Staking", amount, "Tokens staked");
    updateSystemStats();
    
    #ok(account.balance);
  };

  // Unstake tokens
  public func unstakeTokens() : async OperationResult {
    let principal = getCallerPrincipal();
    var account = getAccount(principal);
    
    var originalStakedAmount : Nat = 0; // Initialize with a default value
    let stakingInfo = switch (stakingRecords.get(principal)) {
      case null { return #err("No active staking found") };
      case (?info) { 
        if (not info.isActive) { return #err("Staking is not active") };
        originalStakedAmount := info.amount; // Assign within the case
        applyStakingRewards(principal, info);
      };
    };
    
    let finalAmount = stakingInfo.amount;
    let earnedRewards = finalAmount - originalStakedAmount;
    
    // Update account
    account := {
      account with
      stakedAmount = account.stakedAmount - originalStakedAmount; // Subtract original staked amount
      balance = account.balance + finalAmount;
      totalEarnedStaking = account.totalEarnedStaking + earnedRewards
    };
    
    // Deactivate staking
    stakingRecords.put(principal, {
      stakingInfo with
      isActive = false;
    });
    
    updateAccount(principal, account);
    addTransaction(principal, "Unstake", finalAmount, "Tokens unstaked with rewards");
    updateSystemStats();
    
    #ok(finalAmount);
  };

  // Get staking info
  public func getStakingInfo() : async ?StakingInfo {
    let principal = getCallerPrincipal();
    let stakingInfo = stakingRecords.get(principal);
    
    switch (stakingInfo) {
      case null { null };
      case (?info) { 
        if (info.isActive) {
          ?applyStakingRewards(principal, info);
        } else {
          ?info;
        };
      };
    };
  };

  // -----------------------------
  // Loan Functions
  // -----------------------------

  // Apply for loan
  public func applyForLoan(amount : Nat, termDays : Nat) : async OperationResult {
    if (amount < MIN_LOAN_AMOUNT) return #err("Minimum loan amount is " # Nat.toText(MIN_LOAN_AMOUNT));
    
    let principal = getCallerPrincipal();
    var account = getAccount(principal);
    
    // Check staking requirement
    let stakingInfo = switch (stakingRecords.get(principal)) {
      case null { return #err("Staking required to take a loan") };
      case (?info) { 
        if (not info.isActive) { return #err("Active staking required") };
        applyStakingRewards(principal, info);
      };
    };
    
    let maxLoanAmount = Int.abs(Float.toInt(Float.fromInt(stakingInfo.amount) * MAX_LOAN_TO_STAKING_RATIO));
    if (amount > maxLoanAmount) {
      return #err("Maximum loan amount is " # Nat.toText(maxLoanAmount));
    };
    
    // Create loan
    let loanInfo : LoanInfo = {
      amount = amount;
      principal = amount;
      interestRate = LOAN_INTEREST_RATE;
      startTime = Time.now();
      dueDate = Time.now() + (termDays * 24 * 60 * 60 * 1_000_000_000);
      collateralAmount = stakingInfo.amount;
      status = #active;
    };
    
    // Update account
    account := {
      account with
      balance = account.balance + amount;
      totalLoaned = account.totalLoaned + amount;
      loanCount = account.loanCount + 1
    };
    
    // Store loan record
    let existingLoans = switch (loanRecords.get(principal)) {
      case null { [] };
      case (?loans) { loans };
    };
    loanRecords.put(principal, Array.append(existingLoans, [loanInfo]));
    
    updateAccount(principal, account);
    addTransaction(principal, "Loan", amount, "Loan approved and disbursed");
    updateSystemStats();
    
    #ok(amount);
  };

  // Repay loan
  public func repayLoan(loanId : Nat) : async OperationResult {
    let principal = getCallerPrincipal();
    var account = getAccount(principal);
    
    let loanRecordsList = switch (loanRecords.get(principal)) {
      case null { return #err("No loans found") };
      case (?loans) { loans };
    };
    
    if (loanId >= loanRecordsList.size()) {
      return #err("Invalid loan ID");
    };
    
    var loanInfo = loanRecordsList[loanId];
    if (loanInfo.status != #active) {
      return #err("Loan is not active");
    };
    
    // Calculate interest (simplified)
    let now = Time.now();
    let elapsedDays = (now - loanInfo.startTime) / (24 * 60 * 60 * 1_000_000_000);
    let interest = Int.abs(Float.toInt(Float.fromInt(loanInfo.amount) * loanInfo.interestRate * Float.fromInt(elapsedDays)));
    let totalRepayment = loanInfo.amount + interest;
    
    if (account.balance < totalRepayment) {
      return #err("Insufficient balance for loan repayment");
    };
    
    // Update loan status
    loanInfo := {
      loanInfo with
      status = #completed;
      amount = totalRepayment;
    };
    
    // Update account
    account := {
      account with
      balance = account.balance - totalRepayment
    };
    
    // Update loan records
    let updatedLoans = updateLoanInArray(loanRecordsList, loanId, loanInfo);
    loanRecords.put(principal, updatedLoans);
    
    updateAccount(principal, account);
    addTransaction(principal, "Loan Repayment", totalRepayment, "Loan repayment completed");
    updateSystemStats();
    
    #ok(totalRepayment);
  };

  // Get user loans
  public func getLoanHistory() : async [LoanInfo] {
    let principal = getCallerPrincipal();
    switch (loanRecords.get(principal)) {
      case null { [] };
      case (?loans) { loans };
    };
  };

  // -----------------------------
  // Query Functions
  // -----------------------------

  public func getAccountInfo() : async AccountInfo {
    let principal = getCallerPrincipal();
    var account = getAccount(principal);
    account := applyInterest(account);
    updateAccount(principal, account);
    account;
  };

  public func getTransactionHistory() : async [Transaction] {
    let principal = getCallerPrincipal();
    switch (transactions.get(principal)) {
      case null { [] };
      case (?txs) { txs };
    };
  };

  public query func getSystemConfig() : async {
    interestRate : Float;
    stakingRewardRate : Float;
    loanInterestRate : Float;
    minStakingAmount : Nat;
    minLoanAmount : Nat;
    maxLoanToStakingRatio : Float;
  } {
    {
      interestRate = INTEREST_RATE;
      stakingRewardRate = STAKING_REWARD_RATE;
      loanInterestRate = LOAN_INTEREST_RATE;
      minStakingAmount = MIN_STAKING_AMOUNT;
      minLoanAmount = MIN_LOAN_AMOUNT;
      maxLoanToStakingRatio = MAX_LOAN_TO_STAKING_RATIO;
    };
  };

  // Initialize system with a default account for development
  public func initialize() : async Text {
    let defaultPrincipal = "default-user";
    let _ = createAccount(defaultPrincipal);
    "System initialized successfully";
  };
};
