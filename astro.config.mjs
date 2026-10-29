import { defineConfig } from "astro/config";
import node from "@astrojs/node";
import mdx from "@astrojs/mdx";
import remarkGfm from "remark-gfm";

export default defineConfig({
  output: "server",
  adapter: node({
    mode: "standalone"
  }),
  server: {
    port: 4321,
    host: "0.0.0.0"
  },
  integrations: [mdx()],
  markdown: {
    remarkPlugins: [remarkGfm],
    shikiConfig: {
      themes: {
        light: "github-light",
        dark: "github-dark"
      },
      defaultColor: false,
      wrap: true
    }
  }
});
