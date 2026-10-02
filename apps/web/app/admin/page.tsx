import type { Metadata } from 'next';
import AdminConsole from './console';

export const metadata: Metadata = {
  title: 'Master admin — Paisa',
  description: 'Accounts, households and data for every user of this deployment.',
};

export default function Admin() {
  return <AdminConsole />;
}
