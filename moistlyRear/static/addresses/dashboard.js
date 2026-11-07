const form = document.querySelector('#add-address')
const list = document.querySelector('#watchlist')
const watchError = document.querySelector('#watch-error')
const historySection = document.querySelector('#history')
const historyStatus = document.querySelector('#history-status')
const table = document.querySelector('#transactions')
const body = table.tBodies[0]
const explorer = document.querySelector('#explorer')
const historyRoot = document.querySelector('main').dataset.historyRoot
const storageKey = 'moistly-address-watchlist-v1'
const explorers = { 1: 'https://etherscan.io', 8453: 'https://basescan.org', 42161: 'https://arbiscan.io' }

let watchlist = []
let selected
let historyRequest

try {
  watchlist = JSON.parse(localStorage.getItem(storageKey) ?? '[]')
  if (!Array.isArray(watchlist)) throw new Error('Invalid watchlist')
} catch {
  watchlist = []
  watchError.textContent = 'The saved watchlist could not be read.'
}

function save(entries) {
  try {
    localStorage.setItem(storageKey, JSON.stringify(entries))
  } catch {
    watchError.textContent = 'This browser could not save the watchlist.'
    return false
  }
  watchlist = entries
  watchError.textContent = ''
  renderWatchlist()
  return true
}

function action(label, handler) {
  const button = document.createElement('button')
  button.type = 'button'
  button.textContent = label
  button.addEventListener('click', handler)
  return button
}

function renderWatchlist() {
  list.replaceChildren()
  document.querySelector('#empty-watchlist').hidden = watchlist.length > 0
  for (const entry of watchlist) {
    const item = document.createElement('li')
    const info = document.createElement('div')
    const title = document.createElement('strong')
    title.textContent = entry.label || entry.chainName
    const detail = document.createElement('p')
    detail.textContent = [entry.address, entry.chainName, entry.role].join(' · ')
    info.append(title, detail)
    const controls = document.createElement('div')
    controls.className = 'actions'
    controls.append(action('View history', () => void showHistory(entry)), action('Remove', () => {
      if (save(watchlist.filter(candidate => candidate !== entry)) && selected === entry) {
        historyRequest?.abort()
        selected = undefined
        historySection.hidden = true
      }
    }))
    item.append(info, controls)
    list.append(item)
  }
}

form.addEventListener('submit', event => {
  event.preventDefault()
  const data = new FormData(form)
  const address = data.get('address').trim()
  const role = data.get('role').trim()
  const chain = data.get('chain')
  if (!/^0x[0-9a-f]{40}$/i.test(address) || !role || !Object.hasOwn(explorers, chain)) {
    watchError.textContent = 'Enter a valid EVM address, chain, and role.'
    return
  }
  if (watchlist.some(entry => entry.chain === chain && entry.address.toLowerCase() === address.toLowerCase())) {
    watchError.textContent = 'This address is already tracked on that chain.'
    return
  }
  const entry = { address, role, chain, label: data.get('label').trim(), chainName: form.elements.chain.selectedOptions[0].text }
  if (save([entry, ...watchlist])) form.reset()
})

async function showHistory(entry) {
  historyRequest?.abort()
  const controller = new AbortController()
  historyRequest = controller
  selected = entry
  historySection.hidden = false
  table.hidden = true
  body.replaceChildren()
  document.querySelector('#selected-address').textContent = [entry.address, entry.chainName, entry.role].join(' · ')
  const explorerBase = explorers[entry.chain]
  explorer.href = explorerBase + '/address/' + entry.address
  historyStatus.textContent = 'Loading recent transactions…'

  try {
    const response = await fetch(historyRoot + entry.chain + '/' + encodeURIComponent(entry.address), { signal: controller.signal })
    const data = await response.json()
    if (!response.ok) throw new Error(data.error || 'History is unavailable.')
    if (controller.signal.aborted) return

    for (const tx of data.transactions) {
      const row = body.insertRow()
      const link = document.createElement('a')
      link.href = explorerBase + '/tx/' + encodeURIComponent(tx.hash)
      link.target = '_blank'
      link.rel = 'noopener noreferrer'
      link.textContent = tx.hash.slice(0, 12) + '…'
      link.title = tx.hash
      row.insertCell().append(link)
      const outgoing = tx.from.toLowerCase() === entry.address.toLowerCase()
      const incoming = tx.to.toLowerCase() === entry.address.toLowerCase()
      const direction = outgoing && incoming ? 'Self' : outgoing ? 'Sent' : 'Received'
      const time = tx.timeStamp ? new Date(Number(tx.timeStamp) * 1000).toLocaleString() : '—'
      for (const value of [time, tx.blockNumber, direction, tx.from, tx.to || 'Contract creation', tx.isError === '1' ? 'Failed' : tx.isError === '0' ? 'Success' : 'Unknown']) {
        row.insertCell().textContent = value
      }
    }
    table.hidden = data.transactions.length === 0
    historyStatus.textContent = data.transactions.length
      ? 'Showing the latest ' + data.transactions.length + ' normal transactions.'
      : 'No normal transactions found.'
  } catch (error) {
    if (!controller.signal.aborted) historyStatus.textContent = error.message
  }
}

document.querySelector('#refresh').addEventListener('click', () => {
  if (selected) void showHistory(selected)
})
renderWatchlist()
