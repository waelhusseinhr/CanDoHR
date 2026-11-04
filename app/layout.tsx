import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "CanDoHR",
  description: "CanDoHR. People and positions on this site are sample records until the database is connected.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en-CA">
      <body>{children}</body>
    </html>
  );
}
