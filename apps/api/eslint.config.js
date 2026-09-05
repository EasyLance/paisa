import js from '@eslint/js';

export default [
  js.configs.recommended,
  {
    languageOptions: { ecmaVersion: 2024, sourceType: 'module', globals: { process: 'readonly', console: 'readonly', Buffer: 'readonly', structuredClone: 'readonly' } },
    rules: { 'no-unused-vars': ['error', { argsIgnorePattern: '^_' }] },
  },
];
