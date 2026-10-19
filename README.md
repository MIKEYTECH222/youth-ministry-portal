# Youth Ministry Portal

A bilingual Arabic/English youth ministry website using React + Vite, Supabase Auth/Postgres, and GitHub Pages. It includes member profiles, approval-based signup, point history, events and registrations, study materials, and member/leader/admin roles.

## 1) Create Supabase database
1. Create a project at https://supabase.com/dashboard.
2. Open **SQL Editor → New query**.
3. Open `supabase/schema.sql` in this repository, copy the entire file, paste it into SQL Editor, and click **Run**.
4. In Supabase Project Settings / Connect, copy the **Project URL** and **publishable key** (or legacy `anon` key). Never use `service_role` or a secret key in the browser.

## 2) Run locally on Windows
1. Install Node.js 22 LTS from https://nodejs.org/.
2. Download/extract this project, then open the extracted folder in VS Code.
3. Open Terminal → New Terminal and run:

```powershell
npm install
Copy-Item .env.example .env.local
```

4. Open `.env.local` and replace the example values:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY
```

5. Save, then run:

```powershell
npm run dev
```

6. Open the local URL printed in the terminal (usually http://localhost:5173).

## 3) Create the first administrator
Public signup always creates a `member` with `pending` status. It is not possible to choose admin during signup.
1. Open your local site and create an account using the email that will be the first admin.
2. Confirm that email if Supabase asks you to.
3. In Supabase SQL Editor, run this query after replacing the email:

```sql
update public.profiles
set role = 'admin', status = 'approved'
where id = (
  select id from auth.users where email = 'YOUR-ADMIN-EMAIL-HERE'
);
```

4. Sign out and sign back in. The Administration section should now appear.
5. The admin can approve new members and assign the `leader` role. Promoting another user to admin is intentionally not available from the website; do it manually in SQL as project owner.

## 4) Configure Supabase Auth URLs
In Supabase Authentication → URL Configuration, set the Site URL to your final GitHub Pages URL. Add the local URL `http://localhost:5173/**` and your production URL to allowed redirect URLs. Dashboard labels may change slightly over time.

## 5) Upload to GitHub and publish
1. Create a repository on https://github.com/new. Example: `youth-ministry-portal`.
2. Extract this ZIP and upload the **contents of the folder** (not the ZIP itself) to the repository's `main` branch. Keep hidden files like `.github` and `.gitignore`.
3. On GitHub, open repository **Settings → Secrets and variables → Actions → New repository secret**. Add:
   - `VITE_SUPABASE_URL` = your Supabase Project URL
   - `VITE_SUPABASE_ANON_KEY` = your Supabase publishable/anon key
4. Open **Settings → Pages** and select **GitHub Actions** as the build/deployment source.
5. Open the **Actions** tab and wait for “Deploy to GitHub Pages” to complete successfully. Pushes to `main` redeploy automatically.
6. The site URL is usually `https://YOUR-GITHUB-USERNAME.github.io/youth-ministry-portal/`.
7. Add that exact URL to Supabase Auth URL Configuration and test signup/login again.

The workflow already configures Vite for a repository subpath, so do not change `base` unless using a custom domain.

## Security and limitations
- The SQL file enables Row Level Security (RLS) and uses database policies for authorization. Keep RLS enabled.
- The Supabase URL and publishable/anon key are public browser configuration; that is expected. The `service_role` key is secret and must never be put in frontend code or Vite environment variables.
- New accounts are pending until an admin approves them. Only approved members can see the app's data.
- Only leaders/admins can create events, lessons, and point transactions. Members can read their own point history. Scores are calculated from the transaction ledger, not editable profile fields.
- Permanent account deletion and password reset are not implemented in this starter. Use Supabase dashboard for account deletion, or later add a protected Edge Function. Never put admin secrets in the browser.
- Event registration records interest/registration; it does not verify physical attendance.
- Lesson URLs are external links. For private files, add a private Supabase Storage bucket and signed URLs.
- Test with separate accounts for pending member, approved member, leader, and admin before inviting the whole ministry. Avoid collecting sensitive pastoral information, especially for minors.

## Troubleshooting
- “Supabase setup required”: `.env.local` missing/incorrect; restart Vite after editing it.
- No profile after signup: rerun/check `supabase/schema.sql` and ensure the trigger exists.
- Stays pending: approve the user from the admin account after creating the first admin manually.
- GitHub Pages blank/404: ensure GitHub Pages source is GitHub Actions and the Actions workflow passed.
- Login fails only on the deployed site: add the exact deployed URL to Supabase Auth URL Configuration.
