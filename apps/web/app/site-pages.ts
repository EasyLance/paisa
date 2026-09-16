// Content for the public information pages.
//
// Written to describe what Paisa actually is: an invite-only tool one household
// runs for itself. Nothing here claims a shop, a subscription, a support desk or
// customers that do not exist, and there are no testimonials until somebody
// writes one. Placeholders marked TODO are yours to fill in.

export type SitePage = {
  title: string;
  summary: string;
  sections: { heading: string; body: string[] }[];
};

// TODO: replace with the address you want publicly listed.
const CONTACT_EMAIL = 'hello@easylancefreelance.com';

export const sitePages: Record<string, SitePage> = {
  'about-us': {
    title: 'About Us',
    summary: 'Paisa is a private finance tool for Indian households, built for the people who use it.',
    sections: [
      { heading: 'What it is', body: [
        'Paisa keeps one clear record of what a household earns, spends and sets aside. It reads bank statements you import, captures payment messages on your own phone, and sorts them into categories you control.',
        'It is built around the Indian rupee, the Asia/Kolkata timezone and the way UPI actually reports payments — not adapted from a tool designed somewhere else.',
      ] },
      { heading: 'Who it is for', body: [
        'A household, and anyone that household chooses to share a book with — a spouse, or a chartered accountant who needs to review the year.',
        'Access is by invitation only. There is no public sign-up, and no household can see another household’s books.',
      ] },
      { heading: 'How it is run', body: [
        'Paisa is operated privately rather than sold. It is not a bank, not a payment service, and not a financial adviser.',
      ] },
    ],
  },

  'why-use-us': {
    title: 'Why Use Us',
    summary: 'The reasons this exists rather than a spreadsheet or an off-the-shelf app.',
    sections: [
      { heading: 'Your money stays yours to see', body: [
        'No bank login is ever requested. Paisa never asks for a net-banking password, a UPI PIN or a card number, and it cannot move money. Accounts in Paisa are labels on a ledger, nothing more.',
      ] },
      { heading: 'Nothing is quietly rewritten', body: [
        'Every change is recorded with what the value was before and after. An imported entry keeps the figure the bank sent even if you correct it later, so the original is always recoverable.',
      ] },
      { heading: 'It learns your categories, once', body: [
        'Confirm a payment with “apply to future” and the next payment to the same merchant or UPI ID files itself. Rules only ever affect future payments — nothing you already reviewed is rewritten.',
      ] },
      { heading: 'Built for how Indian banks actually report', body: [
        'Statement imports understand the wrapped narrations SBI produces and the hyphenated UPI strings HDFC produces, including the running-balance column, which is used to check that every amount was read correctly.',
      ] },
    ],
  },

  'my-account': {
    title: 'My Account',
    summary: 'Signing in, your profile, and the books you can see.',
    sections: [
      { heading: 'Signing in', body: [
        'Sign in with the email address your invitation was sent to. Passwords are handled by Firebase Authentication — Paisa never sees or stores your password.',
        'Forgotten it? Use “Forgot your password?” on the sign-in screen and a reset link is emailed to you.',
      ] },
      { heading: 'Your profile', body: [
        'Open the menu under your initials in the top right to change your display name or switch between the books you have access to. Your email address is fixed to the account that was invited.',
      ] },
      { heading: 'Books and roles', body: [
        'A book is one set of finances. You may have a private book of your own and a shared household book. Roles decide what you can do: a viewer reads, a reviewer comments and categorises, an editor records entries, and an owner manages people and settings.',
      ] },
      { heading: 'Leaving', body: [
        'Ask a book owner to remove your access, or write to us and we will remove your account and the personal data attached to it.',
      ] },
    ],
  },

  'help': {
    title: 'Help',
    summary: 'The questions that come up most often.',
    sections: [
      { heading: 'Importing a statement', body: [
        'Accounts & rules → Import statement. CSV and Excel (.xlsx) exports are read on upload and each row is added for review. Re-importing the same file is safe: every row is fingerprinted, so nothing is duplicated.',
        'PDF statements cannot be read yet. Export the same period as CSV or Excel from your bank instead.',
      ] },
      { heading: 'Why does a payment say “needs review”?', body: [
        'Because Paisa has no rule for it yet. Open it, pick a category, and tick “apply to future payments” so the next one files itself.',
      ] },
      { heading: 'Why is my balance not my bank balance?', body: [
        'Balance here means income minus spending minus money moved to your own accounts, for the month shown. It does not include what was in the account before the month began.',
      ] },
      { heading: 'I moved money to my own savings — why is it not spending?', body: [
        'Set the entry’s type to Transfer and choose the destination account. It then counts under Saving rather than Spent, and the movement appears under Accounts.',
      ] },
      { heading: 'Something still looks wrong', body: [
        `Write to ${CONTACT_EMAIL} with the month and the entry, and we will look at it.`,
      ] },
    ],
  },

  'contact-us': {
    title: 'Contact Us',
    summary: 'How to reach the people who run Paisa.',
    sections: [
      { heading: 'Email', body: [
        `${CONTACT_EMAIL} — the best way to reach us, and the address to use for privacy requests, access problems or anything that looks wrong in your ledger.`,
      ] },
      { heading: 'What to include', body: [
        'The book and month you are looking at, and what you expected to see. If it concerns a particular entry, its date and amount are enough to find it. Please never send passwords, UPI PINs or card numbers — we will never ask for them.',
      ] },
      { heading: 'Response time', body: [
        'Paisa is run by a small team alongside other work. Expect a reply within a few working days.',
      ] },
      { heading: 'Reporting a security issue', body: [
        `Write to ${CONTACT_EMAIL} with “security” in the subject and please give us a reasonable chance to fix it before telling anyone else.`,
      ] },
    ],
  },

  'payment-policy': {
    title: 'Payment Policy',
    summary: 'What Paisa charges, and what it can and cannot do with money.',
    sections: [
      { heading: 'There is no charge', body: [
        'Paisa is not sold. There is no subscription, no trial and no in-app purchase, and no payment details are ever collected. If a page ever asks you to pay for Paisa, it is not us.',
      ] },
      { heading: 'Paisa cannot move money', body: [
        'It records payments after they have happened. It holds no funds, initiates no transfers and is not connected to any bank or payment system. Nothing you do here can debit or credit an account.',
      ] },
      { heading: 'Your bank details', body: [
        'Accounts you add are labels — a name, a type and optionally the last four digits so you can tell them apart. Paisa does not ask for and does not store net-banking passwords, UPI PINs, card numbers or CVVs.',
      ] },
    ],
  },

  'customer-service-and-returns-policy': {
    title: 'Customer Service & Returns Policy',
    summary: 'Support, and why there is nothing to return.',
    sections: [
      { heading: 'Returns and refunds', body: [
        'Paisa does not sell goods or services, takes no payment, and therefore has nothing to return and nothing to refund. This page exists so the position is stated plainly rather than left unanswered.',
      ] },
      { heading: 'Support', body: [
        `Email ${CONTACT_EMAIL}. Include the book and month concerned. We aim to reply within a few working days.`,
      ] },
      { heading: 'If you want to stop using Paisa', body: [
        'Ask a book owner to remove your access, or write to us to have your account and personal data deleted. Entries you recorded in a shared book stay in that book’s ledger and audit history, because removing them would leave the household’s records inaccurate.',
      ] },
    ],
  },

  'privacy-policy': {
    title: 'Privacy Policy',
    summary: 'What Paisa holds about you, where it is kept, and what is never collected.',
    sections: [
      { heading: 'What is held', body: [
        'Your name, the email address you were invited with, and a Firebase user identifier. The financial entries in your books: dates, amounts, merchant names as your bank reported them, categories, notes and comments. A record of every change made, including who made it.',
      ] },
      { heading: 'What is never collected', body: [
        'Net-banking passwords, UPI PINs, card numbers and CVVs are never requested and never stored. Paisa has no connection to your bank and cannot sign in to it.',
        'Your password is held by Firebase Authentication, not by Paisa.',
      ] },
      { heading: 'Text messages on your phone', body: [
        'If you use the Android app and grant SMS permission, payment messages are read and parsed on the device itself. Only the resulting fields — amount, date, merchant, a reference number — are sent to the server. The message text stays on your phone.',
      ] },
      { heading: 'Where it is kept', body: [
        'On a private server in a MariaDB database, reachable only over HTTPS. Backups are taken before schema changes and kept on the same server.',
      ] },
      { heading: 'Who can see it', body: [
        'Only people invited to your book, with the role they were given. Households are separated at the database level: no member of one household can read another household’s books through the application.',
        'Nothing is sold, and nothing is shared with advertisers or data brokers. Paisa uses Google Firebase for authentication; their handling of that data is governed by Google’s own privacy policy.',
      ] },
      { heading: 'Your rights', body: [
        `Write to ${CONTACT_EMAIL} to see what is held about you, correct it, or have it deleted.`,
      ] },
    ],
  },

  'cookies': {
    title: 'Cookies',
    summary: 'Paisa sets no tracking cookies and runs no analytics.',
    sections: [
      { heading: 'No tracking, no advertising', body: [
        'There are no analytics scripts, no advertising pixels and no third-party trackers on this site. Nothing follows you between sites, so there is no consent banner to click away.',
      ] },
      { heading: 'What is stored in your browser', body: [
        'Signing in stores your session in your browser’s own local storage so you are not asked for your password on every page. It is used for nothing else, and clearing your browser data or signing out removes it.',
      ] },
      { heading: 'Changing it', body: [
        'You can clear this data from your browser settings at any time. Doing so signs you out; it does not affect anything recorded in your books.',
      ] },
    ],
  },

  'terms-and-conditions': {
    title: 'Terms and Conditions',
    summary: 'The terms on which Paisa is made available.',
    sections: [
      { heading: 'Access is by invitation', body: [
        'Paisa is provided to invited users only. Your invitation is personal to you. Do not share your sign-in details; ask a book owner to invite anyone who needs their own access.',
      ] },
      { heading: 'What you agree to', body: [
        'To use Paisa only for recording finances you are entitled to see, to keep your sign-in details to yourself, and not to attempt to reach data belonging to another household.',
      ] },
      { heading: 'What we provide', body: [
        'Paisa is provided as it is, without warranty. It is operated privately and may change, be interrupted, or be withdrawn. You remain responsible for keeping your own copies of anything you need — every view can be exported to CSV.',
      ] },
      { heading: 'Accuracy is yours to confirm', body: [
        'Imported and captured entries are a convenience, not an authority. Your bank statement is the record that counts. Review what Paisa captures before relying on it.',
      ] },
      { heading: 'Ending access', body: [
        'A book owner may remove your access at any time, and you may ask for your account to be deleted at any time.',
      ] },
      { heading: 'Governing law', body: [
        'These terms are governed by the laws of India.',
      ] },
    ],
  },

  'disclaimer': {
    title: 'Disclaimer',
    summary: 'Paisa is a record-keeping tool, not financial advice.',
    sections: [
      { heading: 'Not financial advice', body: [
        'Nothing in Paisa — a budget, a category, a savings figure or a report — is advice about what you should do with your money. It is a record of what you already did. For advice, speak to a qualified adviser or your chartered accountant.',
      ] },
      { heading: 'Not a tax filing', body: [
        'Paisa does not calculate tax, estimate liability, or prepare or submit returns. Reports exported for your accountant are a starting point for their work, not a substitute for it.',
      ] },
      { heading: 'Your bank is the authority', body: [
        'Amounts read from statements and payment messages can be wrong: a message may be missed, a format may be misread, an entry may be recorded twice. Always check against your bank’s own statement before acting on anything you see here.',
      ] },
      { heading: 'No guarantee of availability', body: [
        'Paisa is run on a single private server. It may be unavailable, and data may be lost despite backups. Keep your own exports of anything that matters.',
      ] },
    ],
  },

  'testimonials-and-feedback': {
    title: 'Testimonials and Feedback',
    summary: 'What people using Paisa have told us — and how to add yours.',
    sections: [
      { heading: 'No testimonials yet', body: [
        'Paisa is used by a small number of invited households and nobody has written a testimonial. Rather than invent one, this page stays empty until somebody does.',
      ] },
      { heading: 'Tell us what is not working', body: [
        `Feedback about something confusing or wrong is far more useful than praise. Email ${CONTACT_EMAIL} with what you expected and what happened instead.`,
      ] },
      { heading: 'Inside the app', body: [
        'You can also leave a note on any individual transaction. Comments are visible to everyone with access to that book and are recorded in its audit history.',
      ] },
    ],
  },

  'blog': {
    title: 'Blog',
    summary: 'Notes on how Paisa works and what has changed.',
    sections: [
      { heading: 'Nothing published yet', body: [
        'There are no posts. When there is something worth writing down — how statement parsing handles a new bank, or what changed in a release — it will appear here.',
      ] },
      { heading: 'In the meantime', body: [
        'The Help page answers the questions that come up most often, and Why Use Us explains the thinking behind how Paisa records money.',
      ] },
    ],
  },
};

export const siteNav = [
  'about-us', 'why-use-us', 'my-account', 'help', 'contact-us',
  'payment-policy', 'customer-service-and-returns-policy', 'terms-and-conditions',
  'privacy-policy', 'cookies', 'disclaimer', 'testimonials-and-feedback', 'blog',
];
