import js from '@eslint/js';

export default [
  js.configs.recommended,
  { languageOptions: { ecmaVersion: 2024, sourceType: 'module', globals: { process: 'readonly', console: 'readonly' } } },
];
