# CanDoHR

CanDoHR is the website for this product. It is on the internet at **[https://candohr.ca](https://candohr.ca)** and **[https://www.candohr.ca](https://www.candohr.ca)**.

The page you see is a starting page. It is not the finished product. You can also open a copy on this computer while you work.

## Start it on this computer

1. Open PowerShell.
2. Go to the project folder:

```powershell
cd C:\Users\wael_\Documents\CanDoHR
```

3. Start the site (only needed the first time, or after the code changes and packages are missing):

```powershell
npx pnpm@9 install
pnpm dev
```

4. On this computer, open [http://localhost:3000](http://localhost:3000).

Leave that PowerShell window open. Closing it stops the site.

## Open it on a phone (same Wi-Fi)

The computer and the phone must be on the same Wi-Fi.

1. On the computer, open PowerShell and run:

```powershell
ipconfig
```

2. Find the **IPv4 Address** for the Wi-Fi connection. It usually looks like `192.168.1.66`. Skip `127.0.0.1` and anything that starts with `169.254`.
3. On the phone’s browser, open `http://` plus that address, plus `:3000`.

Example, if the address is `192.168.1.66`:

[http://192.168.1.66:3000](http://192.168.1.66:3000)

The number can change when the computer reconnects to Wi-Fi. If the phone cannot open the page, run `ipconfig` again and use the new address.

### If Windows asks about the firewall

The first time the site starts, Windows may show a security alert for **Node.js**. It asks whether to allow access on private networks (your home Wi-Fi).

Click **Allow** (private networks). That lets a phone on the same Wi-Fi open the page. You only need to do this once. If you click Cancel, the page still works on this computer, but the phone will not be able to connect.

## What is ready

- **The website** is on Cloudflare and answers at candohr.ca.
- **Email for candohr.ca** still goes to Hostinger. Those mail settings were left as they were.
- **Supabase** is the sign-in and database service. The project is named **CanDo** (it was already on the account and had been paused; it is running again). The database is empty, which is what we want before building features. Sign-in screens are not built yet.
- A file named `.env.local` on this computer holds the public Supabase address and key for local work. It is not uploaded to GitHub.

## What still needs a click from you

- **File storage (R2).** Cloudflare asks you to turn R2 on once in the dashboard before a bucket can be created. Open the Cloudflare dashboard, go to R2, and click to enable it.
- **Hyperdrive** (the fast connection from the website to the Supabase database). This needs the database password from the Supabase dashboard. That password is not stored in this project.
- **GitHub Actions** (automatic publish when code is pushed). This needs a Cloudflare API token saved as a secret on the GitHub repo. Not created yet.

Do not put the Supabase secret service key, the database password, or a Cloudflare token in files that go to GitHub.
