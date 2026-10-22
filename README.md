# IMS Volleyball scores

Fixtures, live scoring and standings for the UoN IMS Volleyball league. It's a single web page hosted free on GitHub Pages, with the data in a free Supabase project.

- **Everyone with the link** can see fixtures and standings, score a match on the Live score tab (and Save it to carry on from another phone), and send the result at the end. Results sent this way count straight away and show as "To check".
- **The organiser** signs in at the bottom of any page ("Organiser sign in") and can then type or change any score, confirm or remove results, import fixtures and edit weeks on the Setup tab. A confirmed result can't be overwritten from Live score.
- The database itself checks every result sent from the public (sets to 25, 25, 15, win by 2, the match must exist), so nobody can get around the rules by bypassing the page.

## Files

| File | What it is |
| --- | --- |
| `index.html` | The whole site |
| `config.js` | Your Supabase URL and public key go here |
| `supabase/schema.sql` | Creates the table, the score checks and the security rules |
| `supabase/seed.sql` | The fixtures for weeks 1–5 and the results for weeks 1–2 |

## Setup (about 15 minutes)

### 1. Supabase

1. Create a new project at [supabase.com](https://supabase.com) (the free plan is plenty). Pick a region in Europe, e.g. London.
2. Open **SQL Editor → New query**, paste in all of `supabase/schema.sql` and press **Run**.
3. New query again, paste in `supabase/seed.sql` and **Run**. This loads the fixtures and results so far.
4. Go to **Authentication → Users → Add user → Create new user**. Enter your email and a password, and tick **Auto Confirm User**.
5. Back in the **SQL Editor**, make that account the organiser (use your own email):

   ```sql
   insert into public.admins (user_id)
   select id from auth.users where email = 'you@example.com';
   ```

6. Optional but tidy: **Authentication → Sign In / Providers → turn off "Allow new users to sign up"**. Other accounts couldn't do anything anyway, since only accounts in `admins` are organisers.
7. Go to **Project Settings → API Keys** (or **Settings → API** on older dashboards). Copy the **Project URL** and the **anon public** key (or the **publishable** key, `sb_publishable_…`). Do not use the `service_role` / secret key.

### 2. Put the keys in `config.js`

```js
window.IMS_CONFIG = {
  supabaseUrl: "https://abcdefghijkl.supabase.co",
  supabaseAnonKey: "eyJhbGciOi…"
};
```

The anon/publishable key is designed to be public: the security rules in `schema.sql` decide what it can do.

### 3. GitHub Pages

1. Create a new **public** repository on GitHub, e.g. `ims-volleyball`.
2. Upload `index.html`, `config.js` and the `supabase` folder (Add file → Upload files), then commit.
3. **Settings → Pages → Build and deployment → Source: Deploy from a branch**, branch `main`, folder `/ (root)`, Save.
4. After a minute the site is live at `https://<your-username>.github.io/ims-volleyball/`. That's the link to send the captains.

### 4. Check it

1. Open the site on your phone. You should see Week 3 with all 18 matches.
2. Scroll to the bottom, tap **Organiser sign in**, and sign in. The **Setup** tab appears.
3. On a computer, open the same link in a private window: no Setup tab and no score boxes to type into, just Score live.

## Day to day

- Results from captains arrive as **To check**. Tap **Confirm** on the Fixtures page when you're happy, or type over the numbers and Submit to correct them. Your own entries are confirmed straight away.
- New fixtures: Setup → paste from Excel or upload the file, then Import. The Spawtz fixture upload template works as is: rows are grouped by date into weeks (a date already on the site goes into that week), and "Hall C Vball 1" becomes Hall C · Court 1. Pick the stage (e.g. Round 1) before importing.
- Results for Spawtz: Setup → Results for Spawtz → pick a week (or all) → Download. You get an .xls in the Spawtz upload template with the sets won as the score, matching the fixtures already in Spawtz. Only confirmed results are included unless you tick the box, and the week 1 default wins for late joiners are left out because they were never Spawtz fixtures.
- On iPhone, Safari can't hide its own bars, so tell scorers to tap **Share → Add to Home Screen** and open the site from that icon. It then runs full screen like an app.
- Live counts that were saved mid-match are cleared automatically when the result is sent.

## Notes

- Free Supabase projects pause after a week with no activity. Weekly use keeps it awake; if it does pause, press **Restore** in the dashboard.
- To add another organiser, create their user in step 1.4 and run step 1.5 with their email.
- To back up, run `select * from docs` in the SQL Editor and download the result as CSV.
