# CanDoHR

CanDoHR is the website for this product. The public address will be **candohr.ca** later. Right now the site only runs on this computer, so you can open it here and on a phone that is on the same Wi-Fi.

The page you see is a starting page. It is not the finished product.

## Start it on this computer

1. Open PowerShell.
2. Go to the project folder:

```powershell
cd C:\Users\wael_\Documents\CanDoHR
```

3. Start the site (only needed the first time, or after the code changes and packages are missing):

```powershell
npm install
npm run dev
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

## What is not set up yet

These are planned. They are not done:

- **Supabase** — sign-in and the database. Not created.
- **Cloudflare** — putting the site on the internet. Not deployed.
- **candohr.ca** — the real web address. Not connected.

Do not put passwords or secret keys in this folder’s files. Nothing secret is stored here yet.
