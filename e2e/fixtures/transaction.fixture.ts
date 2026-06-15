import { test as base } from '@playwright/test'

type TransactionFixtures = {
  createExpense: (opts: { amount: number; description?: string }) => Promise<void>
  createIncome: (opts: { amount: number; description?: string }) => Promise<void>
}

export const test = base.extend<TransactionFixtures>({
  createExpense: async ({ page }, use) => {
    await use(async ({ amount, description }) => {
      await page.goto('/app/transactions/new')
      await page.getByRole('radio', { name: 'Expense' }).click()
      await page.getByLabel('Amount').fill(String(amount))
      if (description) await page.getByLabel('Description').fill(description)
      await page.getByRole('button', { name: 'Save' }).click()
    })
  },
  createIncome: async ({ page }, use) => {
    await use(async ({ amount, description }) => {
      await page.goto('/app/transactions/new')
      await page.getByRole('radio', { name: 'Income' }).click()
      await page.getByLabel('Amount').fill(String(amount))
      if (description) await page.getByLabel('Description').fill(description)
      await page.getByRole('button', { name: 'Save' }).click()
    })
  },
})
