import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "CanDoHR",
  description: "CanDoHR starting page. The public site is not online yet.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
