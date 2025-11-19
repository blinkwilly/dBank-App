import { html, render } from 'lit-html';
import { dbank_backend } from 'declarations/dbank_backend';
import logo from './logo2.svg';

class App {
  balance = 0;
  loading = false;
  message = '';
  error = '';

  constructor() {
    this.currentPeriod = 'daily';
    this.history = [];
    this.isDarkTheme = localStorage.getItem('theme') !== 'light';
    this.stakingInfo = null;
    this.loanHistory = [];
    this.systemConfig = null;
    this.accountInfo = null;
    this.showStaking = false;
    this.showLoans = false;
    this.activeTab = 'dashboard';

    this.#applyTheme();
    this.#loadData();
    this.#render();
  }

  async #loadData() {
    try {
      this.loading = true;
      this.#render();

      const [accountInfo, stakingInfo, loanHistory, systemConfig] = await Promise.all([
        dbank_backend.getAccountInfo().catch(() => null),
        dbank_backend.getStakingInfo().catch(() => null),
        dbank_backend.getLoanHistory().catch(() => []),
        dbank_backend.getSystemConfig().catch(() => null),
      ]);

      this.accountInfo = accountInfo;
      this.balance = accountInfo?.balance || 0n;
      this.stakingInfo = stakingInfo;
      this.loanHistory = loanHistory;
      this.systemConfig = systemConfig;
      this.error = '';
    } catch (err) {
      this.error = 'Failed to load data';
      console.error('Error loading data:', err);
    } finally {
      this.loading = false;
      this.#render();
    }
  }

  async #loadHistory() {
    try {
      this.loading = true;
      this.#render();
      this.history = await dbank_backend.getTransactionHistory().catch(() => []);
      this.error = '';
    } catch (err) {
      this.error = 'Failed to load transaction history';
      console.error(err);
    } finally {
      this.loading = false;
      this.#render();
    }
  }

  #sanitizeInput(input) {
    const value = Math.floor(Number(input.value) || 0);
    return BigInt(value);
  }

  #handleTopUp = async (e) => {
    e.preventDefault();
    const amount = this.#sanitizeInput(document.getElementById('topup-amount'));
    if (amount === 0n) return this.#setError('Please enter a valid amount');

    await this.#performAction(dbank_backend.topUp, amount, `Successfully topped up ${amount} tokens`);
    document.getElementById('topup-amount').value = '';
  };

  #handleWithdraw = async (e) => {
    e.preventDefault();
    const amount = this.#sanitizeInput(document.getElementById('withdraw-amount'));
    if (amount === 0n) return this.#setError('Please enter a valid amount');

    await this.#performAction(dbank_backend.withdraw, amount, `Successfully withdrew ${amount} tokens`);
    document.getElementById('withdraw-amount').value = '';
  };

  #handleStake = async (e) => {
    e.preventDefault();
    const amount = this.#sanitizeInput(document.getElementById('stake-amount'));
    if (amount === 0n) return this.#setError('Please enter a valid amount');

    await this.#performAction(dbank_backend.stakeTokens, amount, `Successfully staked ${amount} tokens`);
    document.getElementById('stake-amount').value = '';
    this.showStaking = false;
  };

  #handleUnstake = async () => {
    await this.#performAction(dbank_backend.unstakeTokens, null, null, 'Successfully unstaked tokens');
    this.showStaking = false;
  };

  #handleApplyLoan = async (e) => {
    e.preventDefault();
    const amount = this.#sanitizeInput(document.getElementById('loan-amount'));
    const termDays = parseInt(document.getElementById('loan-term').value || 0);

    if (amount === 0n || termDays <= 0) return this.#setError('Please enter valid amount and term');

    await this.#performAction(
      dbank_backend.applyForLoan,
      [amount, termDays],
      `Successfully applied for loan of ${amount} tokens`
    );
    document.getElementById('loan-amount').value = '';
    document.getElementById('loan-term').value = '';
    this.showLoans = false;
  };

  #handleRepayLoan = async (loanId) => {
    await this.#performAction(dbank_backend.repayLoan, loanId, null, 'Successfully repaid loan');
  };

  async #performAction(action, args = null, successMsg = '', fallbackMsg = '') {
    try {
      this.loading = true;
      this.#render();
      const result = args !== null ? await action(args) : await action();

      if ('ok' in result) {
        this.balance = result.ok ?? this.balance;
        this.message = successMsg || fallbackMsg || '';
        this.error = '';
        await this.#loadData();
      } else {
        this.#setError(result.err || 'Operation failed');
      }
    } catch (err) {
      this.#setError(fallbackMsg || 'Operation failed');
      console.error(err);
    } finally {
      this.loading = false;
      this.#render();
    }
  }

  #setError(msg) {
    this.error = msg;
    this.message = '';
    this.#render();
  }

  #setActiveTab = (tab) => {
    this.activeTab = tab;
    this.showStaking = false;
    this.showLoans = false;

    if (tab === 'history' && this.history.length === 0) { // Only load history if not already loaded
      this.#loadHistory();
    }
    this.#render();
  };

  #applyTheme = () => {
    document.body.classList.toggle('light-theme', !this.isDarkTheme);
  };

  #toggleTheme = () => {
    this.isDarkTheme = !this.isDarkTheme;
    this.#applyTheme();
    localStorage.setItem('theme', this.isDarkTheme ? 'dark' : 'light');
  };

  #clearMessages = () => {
    this.message = '';
    this.error = '';
    this.#render();
  };

  #calculateStakingRewards = () => {
    if (!this.stakingInfo?.isActive) return 0;
    const timeStaked = Date.now() - this.stakingInfo.startTime / 1_000_000; // convert ns to ms
    const daysStaked = timeStaked / (1000 * 60 * 60 * 24);
    return Math.floor(this.stakingInfo.amount * this.stakingInfo.rewardRate * daysStaked);
  };

  #calculateMaxLoanAmount = () => {
    if (!this.stakingInfo || !this.systemConfig) return 0;
    return Math.floor(this.stakingInfo.amount * this.systemConfig.maxLoanToStakingRatio);
  };

  #render() {
    const body = html`
      <main>
        <img src="${logo}" alt="dBank logo" class="logo" />
        <h1>🏦 dBank Pro - Decentralized Banking Platform</h1>
        <button class="theme-toggle" @click=${this.#toggleTheme}>
          ${this.isDarkTheme ? html`<i class="fas fa-sun"></i>` : html`<i class="fas fa-moon"></i>`}
        </button>

        <!-- Tabs -->
        <div class="tabs">
          ${['dashboard', 'staking', 'loans', 'history'].map(tab => html`
            <button class="tab ${this.activeTab === tab ? 'active' : ''}" 
                    @click=${() => this.#setActiveTab(tab)}>
              ${tab === 'dashboard' ? html`<i class="fas fa-chart-line"></i> Dashboard` :
        tab === 'staking' ? html`<i class="fas fa-lock"></i> Staking` :
          tab === 'loans' ? html`<i class="fas fa-credit-card"></i> Loans` : html`<i class="fas fa-history"></i> History`}
            </button>
          `)}
        </div>

        ${this.loading ? html`<div class="loading"><i class="fas fa-spinner fa-spin"></i> Processing...</div>` : ''}
        ${this.message ? html`<div class="message success" @click=${this.#clearMessages}><i class="fas fa-check-circle"></i> ${this.message}</div>` : ''}
        ${this.error ? html`<div class="message error" @click=${this.#clearMessages}><i class="fas fa-times-circle"></i> ${this.error}</div>` : ''}

        <!-- Content Tabs -->
        ${this.activeTab === 'dashboard' ? this.#dashboardTemplate() : ''}
        ${this.activeTab === 'staking' ? this.#stakingTemplate() : ''}
        ${this.activeTab === 'loans' ? this.#loansTemplate() : ''}
        ${this.activeTab === 'history' ? this.#historyTemplate() : ''}

        <div class="actions">
          <button class="refresh-btn" @click=${() => this.#loadData()} ?disabled=${this.loading}>🔄 Refresh Data</button>
        </div>
      </main>
    `;
    render(body, document.getElementById('root'));
  }

  #dashboardTemplate() {
    return html`
      <div class="dashboard">
        <div class="balance-card">
          <h2><i class="fas fa-wallet"></i> Account Balance</h2>
          <div class="balance-amount">${this.balance.toString()} tokens</div>
          ${this.accountInfo ? html`
            <div class="account-stats">
              <div class="stat"><span>Staked:</span> <span>${this.accountInfo.stakedAmount.toString()} tokens</span></div>
              <div class="stat"><span>Total Earned:</span> <span>${this.accountInfo.totalEarnedStaking.toString()} tokens</span></div>
              <div class="stat"><span>Total Loaned:</span> <span>${this.accountInfo.totalLoaned.toString()} tokens</span></div>
              <div class="stat"><span>Active Loans:</span> <span>${this.accountInfo.loanCount}</span></div>
            </div>
          ` : ''}
        </div>

        ${this.stakingInfo?.isActive ? html`
          <div class="staking-rewards-card">
            <h3><i class="fas fa-trophy"></i> Staking Rewards</h3>
            <p><strong>Staked Amount:</strong> ${this.stakingInfo.amount.toString()} tokens</p>
            <p><strong>Estimated Rewards:</strong> ${this.#calculateStakingRewards()} tokens</p>
            <button class="btn-secondary" @click=${this.#handleUnstake} ?disabled=${this.loading}><i class="fas fa-unlock"></i> Unstake Tokens</button>
          </div>
        ` : html`
          <div class="staking-prompt-card">
            <h3><i class="fas fa-lock"></i> Start Earning Rewards</h3>
            <p>Stake your tokens to earn passive income!</p>
            <button class="btn-primary" @click=${() => this.#setActiveTab('staking')}>Start Staking</button>
          </div>
        `}

        <div class="quick-actions">
          <div class="operation-card">
            <h3><i class="fas fa-arrow-up"></i> Top Up</h3>
            <form @submit=${this.#handleTopUp}>
              <input id="topup-amount" type="number" min="1" placeholder="Enter amount" ?disabled=${this.loading} required />
              <button type="submit" ?disabled=${this.loading}><i class="fas fa-credit-card"></i> Top Up</button>
            </form>
          </div>

          <div class="operation-card">
            <h3><i class="fas fa-arrow-down"></i> Withdraw</h3>
            <form @submit=${this.#handleWithdraw}>
              <input id="withdraw-amount" type="number" min="1" placeholder="Enter amount" ?disabled=${this.loading} required />
              <button type="submit" ?disabled=${this.loading}><i class="fas fa-money-bill-wave"></i> Withdraw</button>
            </form>
          </div>
        </div>
      </div>
    `;
  }

  #stakingTemplate() {
    return html`
      <div class="staking-section">
        <h3><i class="fas fa-lock"></i> Token Staking</h3>
        ${this.systemConfig ? html`
          <p><strong>Minimum Staking:</strong> ${this.systemConfig.minStakingAmount} tokens</p>
          <p><strong>Reward Rate:</strong> ${(this.systemConfig.stakingRewardRate * 100).toFixed(1)}%</p>
        ` : ''}

        ${this.stakingInfo?.isActive ? html`
          <p><strong>Amount Staked:</strong> ${this.stakingInfo.amount.toString()} tokens</p>
          <p><strong>Current Rewards:</strong> ${this.#calculateStakingRewards()} tokens</p>
          <button class="btn-danger" @click=${this.#handleUnstake} ?disabled=${this.loading}><i class="fas fa-unlock"></i> Unstake Now</button>
        ` : html`
          <form @submit=${this.#handleStake}>
            <input id="stake-amount" type="number" min=${this.systemConfig?.minStakingAmount || 1000} placeholder="Enter staking amount" ?disabled=${this.loading} required />
            <button type="submit" ?disabled=${this.loading}><i class="fas fa-lock"></i> Stake Tokens</button>
          </form>
        `}
      </div>
    `;
  }

  #loansTemplate() {
    if (!this.stakingInfo?.isActive) {
      return html`
        <div class="staking-required">
          <p><i class="fas fa-exclamation-triangle"></i> Active staking required to apply for loans</p>
          <button class="btn-primary" @click=${() => this.#setActiveTab('staking')}>Start Staking</button>
        </div>
      `;
    }

    return html`
      <div class="loans-section">
        <h3><i class="fas fa-credit-card"></i> Loan Management</h3>
        <form @submit=${this.#handleApplyLoan}>
          <input id="loan-amount" type="number" min=${this.systemConfig?.minLoanAmount || 500} max=${this.#calculateMaxLoanAmount()} placeholder="Loan amount" ?disabled=${this.loading} required />
          <input id="loan-term" type="number" min="1" max="365" placeholder="Term (days)" ?disabled=${this.loading} required />
          <button type="submit" ?disabled=${this.loading}><i class="fas fa-hand-holding-usd"></i> Apply Loan</button>
        </form>

        <h4><i class="fas fa-chart-bar"></i> Loan History</h4>
        ${this.loanHistory.length === 0 ? html`<p>No loans yet.</p>` : html`
          ${this.loanHistory.map((loan, index) => html`
            <div class="loan-item ${loan.status}">
              <span>Amount: ${loan.amount}</span>
              <span>Status: ${loan.status}</span>
              <span>Interest: ${(loan.interestRate * 100).toFixed(1)}%</span>
              <span>Due: ${new Date(loan.dueDate / 1_000_000).toLocaleDateString()}</span>
              ${loan.status === 'active' ? html`
                <button @click=${() => this.#handleRepayLoan(index)} ?disabled=${this.loading}><i class="fas fa-money-bill-wave"></i> Repay</button>
              ` : ''}
            </div>
          `)}
        `}
      </div>
    `;
  }

  #historyTemplate() {
    return html`
      <div class="history-section">
        <h3><i class="fas fa-history"></i> Transaction History</h3>
        <button class="refresh-btn" @click=${() => this.#loadHistory()} ?disabled=${this.loading}>
          <i class="fas fa-sync-alt"></i> Refresh History
        </button>
        ${this.history.length === 0 ? html`<p>No transactions yet.</p>` : html`
          <div class="transaction-list">
            ${this.history.map(tx => html`
              <div class="transaction-item">
                <div class="tx-header">
                  <span class="tx-type">${tx.txType}</span>
                  <span class="tx-amount">${tx.amount} tokens</span>
                </div>
                <div class="tx-details">
                  <span class="tx-timestamp">${new Date(tx.timestamp / 1_000_000).toLocaleString()}</span>
                  <span class="tx-description">${tx.description}</span>
                </div>
              </div>
            `)}
          </div>
        `}
      </div>
    `;
  }
}

export default App;
