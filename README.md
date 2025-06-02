# DinrusBrew

[![Релиз на GitHub](https://img.shields.io/github/release/Homebrew/brew.svg)](https://github.com/Homebrew/brew/releases)

DinrusBrew - это адаптированная версия Homebrew, которая переведена на русский язык и является вспомогательным средством для использования новых библиотек на операционной системе с установленным комплектом разработки drxtk от DinrusPro.

Эта версия работает несколько иначе; она устанвливает пакеты в префикс DinrusPro/drxtk и, соответственно, использует уже установленные инструменты, т.е. компилятор drux, вместо тех, которые используются в Homebrew.

При дальнейшей разработке DinrusBrew нацелена на интеграцию (или замену) менеджера пакетов eopkg, который используется на ОС "Solux Linux 4.4. Harmony" -
эта операционная система является основной, под которую ведутся разработки DinrusPro.

Что касается дальнейшего текста, то он относится по большей части к Homebrew, который вы можете скачать прямо из его собственного репозитория (, если эта версия вам не подойдёт, т.к. вы не являетесь разработчиком DinrusPro).

Фичи, инструкции по использованию и установке [суммированы на домашней странице](https://brew.sh). Терминология (например, различие между Cellar, Tap, Cask и проч.) [поясняется здесь](https://docs.brew.sh/Formula-Cookbook#homebrew-terminology).

## Какие Пакеты Доступны?

1. Для получения списка введите в терминале `brew formulae`.
2. Либо посетите [formulae.brew.sh](https://formulae.brew.sh), чтобы увидеть пакеты онлайн.

## Дополнительная Документация

Введите в терминале `brew help`, `man brew` или проверьте [нашу документацию](https://docs.brew.sh/) онлайн.

## Решение проблем

Во-первых, пожалуйста, выполните команды `brew update` и `brew doctor`.

Во-вторых, прочтите этот [Контрольный Список по Решению Проблем](https://docs.brew.sh/Troubleshooting).

**Если вы не прочтёте это всё, то нам потребуется гораздо больше времени на то, чтобы помочь вам разобраться.**

## Пожертвования

Homebrew - это "ненаживной" проект (прибыль не на первом месте), запущенный всецело неоплачиваемыми волонтёрами. Нам требуются от вас фонды для оплаты за программное обеспечение, "железо" и хостинг, которые связанны с продолжением интеграции и дальнейшим усовершенствованием нами этого проекта. Каждое пожертвование будет потрачено нами на улучшение Homebrew для всех наших пользователей.

Пожалуйста, примите к сведению информацию о возможности ваших постоянных пожертвований через [Спонсоров GitHub](https://github.com/sponsors/Homebrew), [Открытый Коллектив](https://opencollective.com/homebrew) или [Patreon](https://www.patreon.com/homebrew). Homebrew фискально (налогово) хостируется [Коллективом Open Source](https://opencollective.com/opensource).

По вопросам о пожертвованиях, включая корпоративные отчисления, пожалуйста, отправляйте электронную почту на адрес Homebrew PLC по адресу [plc@brew.sh](mailto:plc@brew.sh).

## Сообщество

- [Homebrew/обсуждения (форум)](https://github.com/orgs/Homebrew/discussions)
- [@homebrew@fosstodon.org (Mastodon)](https://fosstodon.org/@homebrew)
- [@MacHomebrew (𝕏 (ранее известный как Twitter))](https://x.com/MacHomebrew)

## Личный Вклад

Мы будем рады, если вы внесёте свой личный трудовой вклад в проект Homebrew. В начале прочтите наше [Руководство по Сотрудничеству](CONTRIBUTING.md) и [Кодекс Поведения](https://github.com/Homebrew/.github/blob/HEAD/CODE_OF_CONDUCT.md#code-of-conduct).

Мы открыто приветствуем личное участие от людей, ранее никогда не сотрудничавших с проектами с открытым исходным кодом, т.н. "open-source": когда-то мы все были новичками! Далее по-английски: We can help build on a partially working pull request with the aim of getting it merged. We are also actively seeking to diversify our contributors and especially welcome contributions from women from all backgrounds and people of colour.

A good starting point for contributing is to first [tap `homebrew/core`](https://docs.brew.sh/FAQ#can-i-edit-formulae-myself), then run `brew audit --strict` with some of the packages you use (e.g. `brew audit --strict wget` if you use `wget`) and read through the warnings. Try to fix them until `brew audit --strict` shows no results and [submit a pull request](https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request). If no formulae you use have warnings you can run `brew audit --strict` without arguments to have it run on all packages and pick one.

Alternatively, for something more substantial, check out one of the issues labelled `help wanted` in [Homebrew/brew](https://github.com/homebrew/brew/issues?q=is%3Aopen+is%3Aissue+label%3A%22help+wanted%22) or [Homebrew/homebrew-core](https://github.com/homebrew/homebrew-core/issues?q=is%3Aopen+is%3Aissue+label%3A%22help+wanted%22).

Успехов!

## Безопасность

Please report security issues by filling in [the security advisory form](https://github.com/dinrus/brew/security/advisories/new).

## Кто Мы Такие в Homebrew?

Его [Руководителем Проекта](https://docs.brew.sh/Homebrew-Governance#6-project-leader) является [Mike McQuaid](https://github.com/MikeMcQuaid).

Его [Комитет Управления Проектом](https://docs.brew.sh/Homebrew-Governance#4-project-leadership-committee) состоит из [Colin Dean](https://github.com/colindean), [Michka Popoff](https://github.com/iMichka), [Mike McQuaid](https://github.com/MikeMcQuaid), [Patrick Linnane](https://github.com/p-linnane) и [Vanessa Gennarelli](https://github.com/mozzadrella).

В его [Technical Steering Committee](https://docs.brew.sh/Homebrew-Governance#7-technical-steering-committee) входят [Bo Anderson](https://github.com/Bo98), [FX Coudert](https://github.com/fxcoudert), [Mike McQuaid](https://github.com/MikeMcQuaid) и [Rylan Polster](https://github.com/Rylan12).

Homebrew's maintainers are [Alexander Bayandin](https://github.com/bayandin), [Bevan Kay](https://github.com/bevanjkay), [Bo Anderson](https://github.com/Bo98), [Branch Vincent](https://github.com/branchvincent), [Caleb Xu](https://github.com/alebcay), [Carlo Cabrera](https://github.com/carlocab), [Daeho Ro](https://github.com/daeho-ro), [Douglas Eichelberger](https://github.com/dduugg), [Dustin Rodrigues](https://github.com/dtrodrigues), [Eric Knibbe](https://github.com/EricFromCanada), [FX Coudert](https://github.com/fxcoudert), [Issy Long](https://github.com/issyl0), [Justin Krehel](https://github.com/krehel), [Klaus Hipp](https://github.com/khipp), [Markus Reiter](https://github.com/reitermarkus), [Michael Cho](https://github.com/cho-m), [Michka Popoff](https://github.com/iMichka), [Mike McQuaid](https://github.com/MikeMcQuaid), [Nanda H Krishna](https://github.com/nandahkrishna), [Patrick Linnane](https://github.com/p-linnane), [Rui Chen](https://github.com/chenrui333), [Ruoyu Zhong](https://github.com/ZhongRuoyu), [Rylan Polster](https://github.com/Rylan12), [Sam Ford](https://github.com/samford), [Sean Molenaar](https://github.com/SMillerDev), [Štefan Baebler](https://github.com/stefanb), [Thierry Moisan](https://github.com/Moisan), [Timothy Sutton](https://github.com/timsutton) and [William Woodruff](https://github.com/woodruffw).

Former maintainers with significant contributions include [Miccal Matthews](https://github.com/miccal), [Misty De Méo](https://github.com/mistydemeo), [Shaun Jackman](https://github.com/sjackman), [Vítor Galvão](https://github.com/vitorgalvao), [Claudia Pellegrino](https://github.com/claui), [Seeker](https://github.com/SeekingMeaning), [Jan Viljanen](https://github.com/javian), [JCount](https://github.com/jcount), [commitay](https://github.com/commitay), [Dominyk Tiller](https://github.com/DomT4), [Tim Smith](https://github.com/tdsmith), [Baptiste Fontaine](https://github.com/bfontaine), [Xu Cheng](https://github.com/xu-cheng), [Martin Afanasjew](https://github.com/UniqMartin), [Brett Koonce](https://github.com/asparagui), [Charlie Sharpsteen](https://github.com/Sharpie), [Jack Nagel](https://github.com/jacknagel), [Adam Vandenberg](https://github.com/adamv), [Andrew Janke](https://github.com/apjanke), [Alex Dunn](https://github.com/dunn), [neutric](https://github.com/neutric), [Tomasz Pajor](https://github.com/nijikon), [Uladzislau Shablinski](https://github.com/vladshablinsky), [Alyssa Ross](https://github.com/alyssais), [ilovezfs](https://github.com/ilovezfs), [Chongyu Zhu](https://github.com/lembacon) and Homebrew's creator: [Max Howell](https://github.com/mxcl).

## Лицензия

Code is under the [BSD 2-clause "Simplified" License](LICENSE.txt).
Documentation is under the [Creative Commons Attribution license](https://creativecommons.org/licenses/by/4.0/).

## Спонсоры

Our macOS continuous integration infrastructure is hosted by [MacStadium's Orka](https://www.macstadium.com/customers/homebrew).

[![Powered by MacStadium](https://cloud.githubusercontent.com/assets/125011/22776032/097557ac-eea6-11e6-8ba8-eff22dfd58f1.png)](https://www.macstadium.com)

Secure password storage and syncing is provided by [1Password for Teams](https://1password.com/teams/).

[<img src="https://i.1password.com/akb/featured/1password-icon.svg" alt="1Password" height="64">](https://1password.com)

<https://brew.sh>'s DNS is [resolving with DNSimple](https://dnsimple.com/resolving/homebrew).

[![DNSimple](https://cdn.dnsimple.com/assets/resolving-with-us/logo-light.png)](https://dnsimple.com/resolving/homebrew#gh-light-mode-only)
[![DNSimple](https://cdn.dnsimple.com/assets/resolving-with-us/logo-dark.png)](https://dnsimple.com/resolving/homebrew#gh-dark-mode-only)

Homebrew is generously supported by [GitHub](https://github.com/github), [Custom Ink](https://github.com/customink), [Randy Reddig](https://github.com/ydnar), [Codecademy](https://github.com/Codecademy), [MacPaw Inc.](https://github.com/MacPaw), [Workbrew](https://github.com/Workbrew) and many other users and organisations via [GitHub Sponsors](https://github.com/sponsors/Homebrew).

[![GitHub](https://github.com/github.png?size=64)](https://github.com/github)
