// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/dashboard_finanzas_web.ex",
    "../lib/dashboard_finanzas_web/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
      },
      fontSize: {
        'fluid-xs': 'clamp(0.75rem, 0.69rem + 0.3vw, 0.875rem)',
        'fluid-sm': 'clamp(0.875rem, 0.81rem + 0.33vw, 1rem)',
        'fluid-base': 'clamp(1rem, 0.94rem + 0.33vw, 1.125rem)',
        'fluid-lg': 'clamp(1.125rem, 1.06rem + 0.33vw, 1.25rem)',
        'fluid-xl': 'clamp(1.25rem, 1.19rem + 0.33vw, 1.5rem)',
        'fluid-2xl': 'clamp(1.5rem, 1.38rem + 0.66vw, 1.875rem)',
        'fluid-3xl': 'clamp(1.875rem, 1.69rem + 0.98vw, 2.25rem)',
      },
      spacing: {
        'fluid-1': 'clamp(0.25rem, 0.19rem + 0.33vw, 0.5rem)',
        'fluid-2': 'clamp(0.5rem, 0.38rem + 0.66vw, 0.75rem)',
        'fluid-3': 'clamp(0.75rem, 0.56rem + 0.98vw, 1rem)',
        'fluid-4': 'clamp(1rem, 0.75rem + 1.31vw, 1.25rem)',
        'fluid-5': 'clamp(1.25rem, 0.94rem + 1.64vw, 1.5rem)',
        'fluid-6': 'clamp(1.5rem, 1.13rem + 1.97vw, 2rem)',
        'fluid-8': 'clamp(2rem, 1.5rem + 2.62vw, 2.5rem)',
      },
      borderRadius: {
        'fluid': 'clamp(0.5rem, 0.38rem + 0.66vw, 1rem)',
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
        })
      })
      matchComponents({
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          let size = theme("spacing.6")
          if (name.endsWith("-mini")) {
            size = theme("spacing.5")
          } else if (name.endsWith("-micro")) {
            size = theme("spacing.4")
          }
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": size,
            "height": size
          }
        }
      }, {values})
    })
  ]
}
