import { defineConfig } from "vitepress";
import { site } from "../site.js";

const siteUrl = "https://docs.hive.tuist.dev";
const imageUrl = `${siteUrl}/logo.png`;

function routeFor(pageData) {
  const relativePath = pageData.relativePath ?? "index.md";
  const route = relativePath
    .replace(/index\.md$/, "")
    .replace(/\.md$/, "");

  return route ? `/${route}` : "/";
}

export default defineConfig({
  title: "Hive",
  titleTemplate: false,
  description: site.description,
  cleanUrls: true,
  lastUpdated: true,
  sitemap: {
    hostname: "https://docs.hive.tuist.dev",
  },
  head: [
    ["link", { rel: "icon", type: "image/png", href: "/favicon.png" }],
    ["meta", { name: "theme-color", content: "#f59e0b" }],
  ],
  transformHead({ pageData }) {
    const route = routeFor(pageData);
    const baseTitle = pageData.title || "Hive";
    const title = baseTitle === "Hive" ? "Hive" : `${baseTitle} | Hive`;
    const description = pageData.description || site.description;
    const url = `${siteUrl}${route}`;
    const isBlogPost = route.startsWith("/blog/posts/");

    return [
      ["meta", { property: "og:type", content: isBlogPost ? "article" : "website" }],
      ["meta", { property: "og:site_name", content: "Hive" }],
      ["meta", { property: "og:title", content: title }],
      ["meta", { property: "og:description", content: description }],
      ["meta", { property: "og:url", content: url }],
      ["meta", { property: "og:image", content: imageUrl }],
      ["meta", { name: "twitter:card", content: "summary_large_image" }],
      ["meta", { name: "twitter:title", content: title }],
      ["meta", { name: "twitter:description", content: description }],
      ["meta", { name: "twitter:image", content: imageUrl }],
      ["link", { rel: "canonical", href: url }],
      ...(route === "/blog/"
        ? [
            ["link", { rel: "alternate", type: "application/atom+xml", href: `${siteUrl}/blog/atom.xml` }],
            ["link", { rel: "alternate", type: "application/rss+xml", href: `${siteUrl}/blog/rss.xml` }],
          ]
        : []),
    ];
  },
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
