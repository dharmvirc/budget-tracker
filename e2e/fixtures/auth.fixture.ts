import { test as base, expect, Page } from '@playwright/test'

type AuthFixtures = {
  loginAs: (email: string, password: string) => Promise<void>
  loginAsAdmin: () => Promise<void>
}

export const test = base.extend<AuthFixtures>({
  loginAs: async ({ page }, use) => {
    await use(async (email: string, password: string) => {
      await page.goto('/login')
      await page.getByLabel('Email').fill(email)
      await page.getByLabel('Password').fill(password)
      await page.getByRole('button', { name: 'Sign in' }).click()
      await expect(page).toHaveURL('/app/dashboard')
    })
  },
  loginAsAdmin: async ({ page }, use) => {
    await use(async () => {
      await page.goto('/login')
      await page.getByLabel('Email').fill('admin@budgettracker.local')
      await page.getByLabel('Password').fill('Admin@1234')
      await page.getByRole('button', { name: 'Sign in' }).click()
    })
  },
})

export { expect } from '@playwright/test'
