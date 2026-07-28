import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "SalesSetu – Real Estate Lead Automation & AI Call Bot",
  description:
    "SalesSetu is an AI-powered real estate lead automation platform that instantly calls, qualifies, and filters property leads from Meta Ads and Google Ads.",
  keywords: [
    "real estate lead automation",
    "AI call bot for real estate",
    "property lead qualification",
    "real estate CRM automation",
    "real estate AI voice bot",
    "automate real estate leads",
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}