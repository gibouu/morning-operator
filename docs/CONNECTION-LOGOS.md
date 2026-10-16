# Connection logos

The connections screen uses bundled brand artwork at 24 pt inside a 32 pt tile.
PNG variants at 24, 48 and 72 px retain the source artwork's colors and proportions.
No artwork is fetched at runtime. The asset catalog is already included by `project.yml`.

## Sources

Artwork was retrieved on 16 October 2026. Names identify services; their trademarks
remain the property of their respective owners and do not imply endorsement.

All assets except Google Docs and Le Monde come from [SVGL](https://github.com/pheralb/svgl),
pinned at [f9b726cee1d1f3c697a18c880185e89d9a55bb70](https://github.com/pheralb/svgl/tree/f9b726cee1d1f3c697a18c880185e89d9a55bb70/static/library).

| Asset service ID | Upstream SVG filename |
| --- | --- |
| instagram | instagram-icon.svg |
| tiktok | tiktok-icon-light.svg |
| twitter (X) | x.svg |
| whatsapp | whatsapp-icon.svg |
| reddit | reddit.svg |
| facebook | facebook-icon.svg |
| threads | threads.svg |
| youtube | youtube.svg |
| gmail | gmail.svg |
| outlook | microsoft-outlook.svg |
| googlecalendar | google-calendar.svg |
| googledrive | drive.svg |
| googlesheets | google-sheets.svg |
| notion | notion.svg |
| slack | slack.svg |
| calendly | calendly.svg |
| linkedin | linkedin.svg |
| discord | discord.svg |

Google Docs uses [Simple Icons 14.11.0](https://github.com/simple-icons/simple-icons/blob/14.11.0/icons/googledocs.svg)
with its upstream brand color `#4285F4`. Simple Icons artwork is released under
[CC0 1.0](https://github.com/simple-icons/simple-icons/blob/14.11.0/LICENSE.md).

The SVG files were rasterized with `rsvg-convert --width N --height N` for
`N = 24, 48, 72`. To update an image, retrieve its pinned upstream SVG, render those
three sizes and replace the corresponding `Connection-<service>.imageset` files.

The `news` asset identifies Le Monde. Its official [180 px site icon](https://www.lemonde.fr/bucket/resources/front/static/img/logos/pwa-180.png)
was discovered in the `apple-touch-icon` and `icon` links on the [Le Monde homepage](https://www.lemonde.fr/)
on 16 October 2026, then resized to the same three sizes with Lanczos resampling.
The source SHA-256 is `60020297e849f118df6d6f305be9aad92280ba5abc2e4f6d25b93adeb1ba2de2`.
This artwork belongs to Le Monde and is used solely to identify the linked service;
it is not covered by the SVGL or Simple Icons licenses.

## SVGL license

MIT License

Copyright (c) 2022 Pablo Hdez

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
