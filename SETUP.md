# The Gratitude Wall: setup guide

What's in this folder:

| File | What it is |
|---|---|
| `site/index.html` | The whole website (goes on Vercel): the daily form **and** the shared wall (`yoursite/#wall`). One file, no build step. |
| `supabase/schema.sql` | Creates the tables and the safe functions the site uses. |
| `supabase/functions/send-letters/index.ts` | The Dec 31 job: an AI model on Groq (free) writes each person's letter, then it's emailed to them. |
| `supabase/schedule.sql` | Makes the letter job run by itself on Dec 31. |

How it works: people write on the site every day → entries go into Supabase → on Dec 31 from 6pm Lagos time a job runs every 2 minutes, writes each person a letter from **all** their entries (private ones included) and emails it. Each letter is also saved in the `gw_letters` table, so nothing is lost if an email bounces.

You can do steps 1–2 today and launch. Steps 3–6 only need to be done before Dec 31.

---

## 1. Database (10 min)

1. Open your Supabase project (your March one is fine, since nothing here touches the old `entries` table) or create a new one.
2. **SQL Editor → New query** → paste all of `supabase/schema.sql` → **Run**. You should see "Success".
3. Click the **Connect** button at the top of your project dashboard. Copy the **Project URL** (`https://xxxx.supabase.co`) and the **publishable key** (starts with `sb_publishable_`).
   - You can also find the key under **Project Settings → API Keys**.
   - Use the publishable key, not the old "anon" key: Supabase is retiring the old keys around the end of 2026, right when your letters go out.

## 2. Website on Vercel (15 min, free)

**Fill in your settings first**
1. Open `site/index.html` in VS Code. Near the bottom, find the `CONFIG` block and fill in:
   - `SUPABASE_URL` and `SUPABASE_ANON_KEY` (paste the publishable key from step 1.3 here)
   - `CHALLENGE_NAME`, `START_DATE`, `END_DATE`, `HOST` if you want to change them
2. Save. Optional: double-click the file to check it opens in your browser.

**Put it on GitHub**
3. On github.com: **New repository** → name it e.g. `gratitude-wall` → **Create repository**. Public is fine (there are no secrets in the code), or choose Private.
4. On the new repo page, click **uploading an existing file**, drag in **everything inside** the `gratitude-wall` folder (the `site` and `supabase` folders, README.md, SETUP.md, .gitignore) → **Commit changes**.

**Deploy on Vercel**
5. Go to **vercel.com** → sign up with your GitHub account (the free Hobby plan).
6. **Add New → Project** → find `gratitude-wall` → **Import**. If it's not listed, click **Adjust GitHub App Permissions** and allow that repo.
7. Set **Framework Preset** to **Other**, and set **Root Directory** to `site` (click **Edit** next to it). Leave everything else as default → **Deploy**.
8. In about a minute you'll get a link like `gratitude-wall.vercel.app`. If that name was taken, Vercel adds random letters; change it under **Project → Settings → Domains → Edit** to any free `something.vercel.app` name.
9. Test it: submit an entry, then open `yoursite.vercel.app/#wall`.

**Making changes later:** edit `index.html` on GitHub (pencil icon) or upload a new version. Vercel republishes automatically within a minute.

Share one link: `yoursite.vercel.app`. The wall is the "The wall" tab, or link straight to `#wall`.

> The publishable key is meant to be public, so it's fine in the file. The tables are locked: the site can only call three functions, and those never return emails or private entries. The wall shows first names only. Never put your Groq, Brevo or admin secrets in this file; they go in Supabase only (step 5).

## 3. Groq API key (5 min, free)

1. Go to **console.groq.com** and sign up. No card needed.
2. **API Keys → Create API Key**. Copy it (it starts with `gsk_`).

The free plan writes roughly **80 letters a day**. If more people join than that, the job keeps going on Jan 1–3 until everyone has theirs (see step 6). Your exact limits are under **Settings → Limits** in the Groq console.

Want faster or more polished letters later? Swap to a paid model by changing the code back to Claude. Ask Claude to do it.

## 4. Email sender: Brevo (10–30 min)

1. Sign up free at **brevo.com**. The free plan allows about 300 emails a day.
2. **Senders, domains & dedicated IPs → Senders → Add a sender** with the email you want letters to come from.
3. **SMTP & API → API keys → Generate a new API key**. Copy it.

**Important: Gmail vs your own domain.** If your sender is a `@gmail.com` address, Brevo still sends, but it swaps the "from" address for one of its own, and more letters will land in spam. For letters people actually see, buy a cheap domain (about $10/year from Namecheap, Porkbun, etc.), add it under **Domains → Add a domain** in Brevo, and follow its DNS steps. Then send from something like `letters@yourdomain.com`. You could point the same domain at your Vercel site too.

## 5. The letter function (15 min)

1. Supabase → **Edge Functions → Deploy a new function → Via Editor**.
2. Name it exactly `send-letters`. Delete the sample code, paste all of `supabase/functions/send-letters/index.ts`, and **Deploy**.
   Then open the function's **Details / Settings** and turn **off** "Verify JWT" (also called "Enforce JWT verification"). The function has its own password check (`ADMIN_SECRET`), and this lets the schedule call it without the old anon key.
3. **Edge Functions → Secrets**: add these (name → value):

| Name | Value |
|---|---|
| `ADMIN_SECRET` | Any long password you make up. It stops strangers from triggering the job. |
| `GROQ_API_KEY` | from step 3 |
| `BREVO_API_KEY` | from step 4 |
| `SENDER_EMAIL` | the sender you added in Brevo |
| `SENDER_NAME` | e.g. `Dammie` |
| `CHALLENGE_NAME` | same as on the site, e.g. `The Gratitude Wall` |
| `SITE_URL` | e.g. `https://yoursite.vercel.app` (adds a "see the wall" link in the email) |

Optional: `GROQ_MODEL` (default `openai/gpt-oss-120b`), `BATCH_SIZE` (default `2`; keep it small on the free plan).

### Test it (do this a week or so before Dec 31)

Open the function → **Test** (top right). Set method `POST`, add the header `x-admin-secret` = your ADMIN_SECRET, and use one of these bodies:

- See a letter without sending anything:
  `{ "mode": "preview", "email": "an-email-that-has-entries@example.com" }`
- Get a real email of someone's letter sent **to you only**:
  `{ "mode": "test", "email": "their@email.com", "to": "you@email.com" }`
- Check progress any time: `{ "mode": "status" }`

Same thing from a terminal, if you prefer:

```bash
curl -X POST https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-letters \
  -H "x-admin-secret: YOUR_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"mode":"preview","email":"you@email.com"}'
```

Don't like the tone of the letters? Edit `SYSTEM_PROMPT` near the top of `index.ts`, redeploy, and preview again.

## 6. Schedule Dec 31 (5 min)

1. Make a copy of `supabase/schedule.sql` named `schedule.local.sql` (it's git-ignored, so your admin secret never ends up on GitHub). In the copy, replace `YOUR_PROJECT_REF` (the bit before `.supabase.co` in your URL) and `YOUR_ADMIN_SECRET`.
2. Paste it into the **SQL Editor → Run**.

This creates two schedules:
- **Dec 31, 6pm to midnight Lagos time:** every 2 minutes, 2 letters per run.
- **Jan 1–3:** keeps going for anyone left over after Groq's daily cap resets. Once everyone has a letter, each run just says "done".

Times in the file are in UTC (one hour behind Lagos).

### On the day

- Check progress: send `{ "mode": "status" }` from the Test panel, or run
  `select letter_status, count(*) from gw_participants group by 1;`
- Rate limits are handled for you: if Groq says "slow down" or the daily cap is reached, that person goes back in the queue and is picked up on a later run.
- If some say `failed`, see why with `select email, letter_error from gw_participants where letter_status = 'failed';`, then send `{ "mode": "retry_failed" }` and the schedule will pick them up again.
- Resend to one person: `{ "mode": "send", "email": "them@email.com" }`.
- Brevo's free plan stops at about 300 emails a day, so Groq's ~80 letters a day is the tighter limit.

## Good to know

- People don't need accounts. Their email is their identity, so tell them to use the same email every day.
- Up to 5 entries per person per day (simple spam guard).
- "Only for my letter" entries never appear on the wall, but they are in the letter.
- Anyone who knows someone's email could add an entry under it. That's fine for a friendly community challenge, but don't use this for anything sensitive.
- To remove an entry from the wall: Supabase → **Table Editor → gw_entries** → find it → set `visibility` to `private`, or delete the row.
