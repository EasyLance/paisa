import type { Metadata } from 'next';
import { SignInPage } from '../sign-in';

export const metadata: Metadata = {
  title: 'Login — Paisa',
  description: 'Sign in to your Paisa household book. Access is by invitation only.',
};

export default function Login() {
  return <SignInPage />;
}
