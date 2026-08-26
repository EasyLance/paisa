'use client';

import { FormEvent, useEffect, useMemo, useState } from 'react';

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4000';
const demoTransactions = [
  { id:'tx_1', merchant:'Swiggy', occurredAt:'2026-08-26T14:20:00.000Z', state:'confirmed', kind:'expense', amountMinor:'-75000', categoryId:'cat_food', meta:'Today · UPI' },
  { id:'tx_2', merchant:'Hostel EMI', occurredAt:'2026-08-26T09:10:00.000Z', state:'pending_review', kind:'expense', amountMinor:'-3500000', categoryId:'cat_emi', meta:'Today · Auto-detected' },
  { id:'tx_3', merchant:'Acme Technologies', occurredAt:'2026-08-25T05:30:00.000Z', state:'reconciled', kind:'income', amountMinor:'58786700', categoryId:'cat_salary', meta:'25 Aug · Bank credit' },
  { id:'tx_4', merchant:'Electricity bill', occurredAt:'2026-08-24T10:45:00.000Z', state:'confirmed', kind:'expense', amountMinor:'-234000', categoryId:'cat_utilities', meta:'24 Aug · UPI' },
];
const demoCategories = [
  {id:'cat_food',name:'Food delivery'}, {id:'cat_emi',name:'EMI'}, {id:'cat_salary',name:'Salary'}, {id:'cat_utilities',name:'Utilities'},
  {id:'cat_groceries',name:'Groceries'}, {id:'cat_dining',name:'Dining out'}, {id:'cat_transport',name:'Transportation'}, {id:'cat_other',name:'Uncategorized'},
];

type Book = { id:string; name:string; visibility:string; role:string };
type Category = { id:string; name:string };
type Transaction = { id:string; merchant:string|null; occurredAt:string; state:string; kind:string; amountMinor:string; categoryId:string|null; meta?:string };
type Summary = { incomeMinor:string; spentMinor:string; savedMinor:string; pendingReview:number };

function money(minor:string, signed=false) {
  const value = Number(BigInt(minor)) / 100;
  const absolute = new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:0}).format(Math.abs(value));
  if (!signed) return absolute;
  return value > 0 ? `+${absolute}` : value < 0 ? `−${absolute}` : absolute;
}

function api(path:string, options:RequestInit={}) {
  return fetch(`${API_URL}${path}`, { ...options, headers:{'content-type':'application/json','x-dev-user-id':'user_owner',...options.headers} }).then(async response => {
    if (!response.ok) throw new Error((await response.json()).message ?? 'Request failed');
    return response.json();
  });
}

export default function Home() {
  const [books,setBooks] = useState<Book[]>([{id:'book_arjun',name:"Arjun's finances",visibility:'private',role:'book_owner'},{id:'book_home',name:'Household',visibility:'shared',role:'book_owner'}]);
  const [bookId,setBookId] = useState('book_arjun');
  const [summary,setSummary] = useState<Summary>({incomeMinor:'58786700',spentMinor:'28755000',savedMinor:'30031700',pendingReview:3});
  const [transactions,setTransactions] = useState<Transaction[]>(demoTransactions);
  const [categories,setCategories] = useState<Category[]>(demoCategories);
  const [dialog,setDialog] = useState<'add'|'review'|null>(null);
  const [toast,setToast] = useState('');
  const [saving,setSaving] = useState(false);
  const activeBook = books.find(book=>book.id===bookId) ?? books[0];
  const categoryMap = useMemo(()=>Object.fromEntries(categories.map(category=>[category.id,category.name])),[categories]);
  const pending = transactions.find(transaction=>transaction.state==='pending_review');

  async function refresh(selected=bookId) {
    try {
      const [bookData,summaryData,transactionData,categoryData] = await Promise.all([
        api('/v1/books'), api(`/v1/books/${selected}/summary`), api(`/v1/books/${selected}/transactions?limit=20`), api(`/v1/books/${selected}/categories`),
      ]);
      setBooks(bookData.items); setSummary(summaryData); setTransactions(transactionData.items); setCategories(categoryData.items);
    } catch { /* The designed demo stays usable while the local API is offline. */ }
  }
  useEffect(()=>{ refresh(bookId); },[bookId]);

  async function addTransaction(event:FormEvent<HTMLFormElement>) {
    event.preventDefault(); setSaving(true);
    const form = new FormData(event.currentTarget); const rupees = String(form.get('amount') ?? '0').replace(/,/g,''); const kind=String(form.get('kind'));
    const minor=(BigInt(Math.round(Number(rupees)*100))*(kind==='expense'?-1n:1n)).toString();
    try {
      await api(`/v1/books/${bookId}/transactions`,{method:'POST',headers:{'idempotency-key':crypto.randomUUID()},body:JSON.stringify({kind,amountMinor:minor,merchant:String(form.get('merchant')),categoryId:String(form.get('categoryId')),occurredAt:new Date().toISOString()})});
      await refresh(); setDialog(null); setToast('Transaction added to your book');
    } catch(error) { setToast(error instanceof Error?error.message:'Could not add transaction'); }
    finally { setSaving(false); setTimeout(()=>setToast(''),3000); }
  }

  async function confirmCategory(event:FormEvent<HTMLFormElement>) {
    event.preventDefault(); if(!pending)return; setSaving(true); const form=new FormData(event.currentTarget);
    try {
      await api(`/v1/books/${bookId}/transactions/${pending.id}/category`,{method:'PATCH',body:JSON.stringify({categoryId:String(form.get('categoryId')),applyToFuture:form.get('future')==='on'})});
      await refresh(); setDialog(null); setToast('Payment confirmed and audit trail updated');
    } catch(error) { setToast(error instanceof Error?error.message:'Could not confirm payment'); }
    finally { setSaving(false); setTimeout(()=>setToast(''),3000); }
  }

  const stats=[{label:'Income',value:money(summary.incomeMinor),detail:'Received this month',tone:'mint'},{label:'Spent',value:money(summary.spentMinor),detail:`${summary.incomeMinor==='0'?'0':((Number(summary.spentMinor)/Number(summary.incomeMinor))*100).toFixed(1)}% of income`,tone:'coral'},{label:'Saved',value:money(summary.savedMinor),detail:'Available after spending',tone:'navy'}];

  return <main className="app-shell">
    <aside className="sidebar"><div className="brand"><span className="brand-mark">₹</span><span>Paisa</span></div><nav aria-label="Primary navigation">
      <a className="nav-item active" href="#overview"><span>⌂</span>Overview</a><a className="nav-item" href="#transactions"><span>⇄</span>Transactions</a><a className="nav-item" href="#budgets"><span>◌</span>Budgets</a><a className="nav-item" href="#reports"><span>↗</span>Reports</a><a className="nav-item" href="#people"><span>◉</span>People & access</a>
    </nav><div className="sidebar-footer"><p>Your workspace</p><label className="workspace-switcher"><span className="avatar small">AM</span><span>{activeBook?.name}<small>{activeBook?.visibility} book</small></span><select aria-label="Select financial book" value={bookId} onChange={event=>setBookId(event.target.value)}>{books.map(book=><option value={book.id} key={book.id}>{book.name}</option>)}</select></label></div></aside>
    <section className="main-panel" id="overview"><header className="topbar"><div><p className="eyebrow">Wednesday, 26 August</p><h1>Good evening, Arjun</h1></div><div className="top-actions"><button className="icon-button" aria-label="Notifications">●<span className="notification-dot" /></button><button className="primary-button" onClick={()=>setDialog('add')}>+ Add transaction</button><span className="avatar">AM</span></div></header>
      <div className="content"><section className="review-banner"><div className="review-icon">✓</div><div><strong>{summary.pendingReview} payments need a quick review</strong><p>We captured them automatically. Confirm the categories while they&apos;re fresh.</p></div><button onClick={()=>setDialog('review')} disabled={!pending}>Review now <span>→</span></button></section>
        <div className="stats-grid">{stats.map(stat=><article className={`stat-card ${stat.tone}`} key={stat.label}><div className="stat-head"><span>{stat.label}</span><i /></div><strong>{stat.value}</strong><small>{stat.detail}</small></article>)}</div>
        <div className="dashboard-grid"><article className="card spending-card"><div className="card-header"><div><p className="eyebrow">MONTHLY SPENDING</p><h2>Where your money went</h2></div><button className="period-button">August 2026 ⌄</button></div><div className="spending-body"><div className="donut" aria-label="Monthly spending ratio"><div><strong>{summary.incomeMinor==='0'?'0':((Number(summary.spentMinor)/Number(summary.incomeMinor))*100).toFixed(1)}%</strong><span>of income</span></div></div><div className="legend"><div><span className="legend-dot essential"/><p><b>Essentials</b><small>Rent, bills, groceries</small></p><strong>₹1,92,750</strong></div><div><span className="legend-dot lifestyle"/><p><b>Lifestyle</b><small>Dining, travel, shopping</small></p><strong>₹94,800</strong></div><button>View all categories <span>→</span></button></div></div></article>
          <article className="card budget-card" id="budgets"><div className="card-header"><div><p className="eyebrow">BUDGET HEALTH</p><h2>August plan</h2></div><button className="more-button" aria-label="More options">···</button></div><div className="budget-total"><div><strong>₹2,87,550</strong><span>of ₹3,20,000</span></div><b>90%</b></div><div className="progress"><span /></div>{[['Groceries','₹4,820 / ₹6,000','80%'],['Dining out','₹2,300 / ₹2,500','92%'],['Transportation','₹3,460 / ₹6,000','58%']].map(([name,value,width])=><div className={`budget-row ${name==='Dining out'?'warning':''}`} key={name}><span>{name}</span><b>{value}</b><i><em style={{width}} /></i></div>)}</article></div>
        <article className="card transactions-card" id="transactions"><div className="card-header"><div><p className="eyebrow">RECENT ACTIVITY</p><h2>Latest transactions</h2></div><button className="text-button">See all transactions <span>→</span></button></div><div className="transaction-list">{transactions.slice(0,5).map((tx,index)=><div className="transaction" key={tx.id}><span className={`transaction-mark ${['peach','blue','green','gold'][index%4]}`}>{(tx.merchant??'?')[0]}</span><div className="transaction-name"><strong>{tx.merchant??'Transaction'}</strong><small>{tx.meta??new Date(tx.occurredAt).toLocaleDateString('en-IN',{day:'numeric',month:'short'})} · {tx.state.replace('_',' ')}</small></div><span className="category-pill">{categoryMap[tx.categoryId??'']??'Uncategorized'}</span><strong className={tx.kind==='income'?'positive':''}>{money(tx.amountMinor,true)}</strong></div>)}</div></article>
      </div>
    </section>
    {dialog==='add'&&<div className="modal-backdrop" role="presentation" onMouseDown={()=>setDialog(null)}><section className="modal" role="dialog" aria-modal="true" aria-labelledby="add-title" onMouseDown={event=>event.stopPropagation()}><button className="modal-close" onClick={()=>setDialog(null)} aria-label="Close">×</button><p className="eyebrow">MANUAL ENTRY</p><h2 id="add-title">Add a transaction</h2><p className="modal-copy">Use this for cash or when automatic capture is unavailable.</p><form onSubmit={addTransaction}><label>Merchant or source<input name="merchant" required placeholder="e.g. Local grocery store" /></label><div className="form-row"><label>Type<select name="kind"><option value="expense">Expense</option><option value="income">Income</option><option value="refund">Refund</option></select></label><label>Amount in rupees<input name="amount" inputMode="decimal" pattern="[0-9,]+(\\.[0-9]{1,2})?" required placeholder="0" /></label></div><label>Category<select name="categoryId">{categories.map(category=><option value={category.id} key={category.id}>{category.name}</option>)}</select></label><button className="primary-button submit" disabled={saving}>{saving?'Saving…':'Add transaction'}</button></form></section></div>}
    {dialog==='review'&&pending&&<div className="modal-backdrop" role="presentation" onMouseDown={()=>setDialog(null)}><section className="modal" role="dialog" aria-modal="true" aria-labelledby="review-title" onMouseDown={event=>event.stopPropagation()}><button className="modal-close" onClick={()=>setDialog(null)} aria-label="Close">×</button><p className="eyebrow">AUTOMATIC CAPTURE</p><h2 id="review-title">Does this category look right?</h2><div className="review-transaction"><span>{(pending.merchant??'?')[0]}</span><div><strong>{pending.merchant}</strong><small>{new Date(pending.occurredAt).toLocaleString('en-IN')}</small></div><b>{money(pending.amountMinor,true)}</b></div><form onSubmit={confirmCategory}><label>Category<select name="categoryId" defaultValue={pending.categoryId??'cat_other'}>{categories.map(category=><option value={category.id} key={category.id}>{category.name}</option>)}</select></label><label className="checkbox"><input type="checkbox" name="future" /> Use this category for the same merchant in future</label><button className="primary-button submit" disabled={saving}>{saving?'Confirming…':'Confirm payment'}</button></form></section></div>}
    {toast&&<div className="toast" role="status">{toast}</div>}
  </main>;
}
