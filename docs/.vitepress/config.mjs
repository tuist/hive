import { defineConfig } from "vitepress";
import { site } from "../site.js";

export default defineConfig({
  title: "Hive",
  titleTemplate: false,
  description: site.description,
  cleanUrls: true,
  lastUpdated: true,
  sitemap: {
    hostname: "https://docs.hive.tuist.dev",
    transformItems: (items) =>
      items.filter(
        (item) => !item.url.includes("guide/self-hosting/agents"),
      ),
  },
  head: [
    ["link", { rel: "icon", type: "image/png", href: "/favicon.png" }],
    ["meta", { name: "theme-color", content: "#f59e0b" }],
  ],
  themeConfig: {
    logo: "/nav-logo.png",
    search: {
      provider: "local",
    },
    editLink: {
      pattern: "https://github.com/tuist/hive/edit/main/docs/:path",
      text: "Edit this page on GitHub",
    },
    nav: site.nav,
    sidebar: site.sidebar,
    socialLinks: [{ icon: "github", link: "https://github.com/tuist/hive" }],
    footer: site.footer,
  },
});
