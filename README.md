# AutoDivert

> [!IMPORTANT]
> - AutoDivert — это утилита, некая "История браузера" но глобальна для всего Компьютера
> - История хранит все подключения пк: сайты, сервера игр, и т.д. сохраняя их в формате `ip.адрес домен.com`
> - Если у вас перестал работать сайт, игра, и т.д. то попробуйте найти нужный Адрес-Домен в файле `hosts.txt` (Появляется после первого запуска) и вставить его по этому пути: `C:\Windows\System32\drivers\etc\hosts`

> [!TIP]
> - AutoDivert и [AutoLoader](https://github.com/reddflower/zapret_autoloader) имеют обратную совместимость, по этому вы можете поместить AutoDivert в одну папку с AutoLoader
> - Во время работы АвтоДиверта все процессы будут записываться в данный Лог: `collector.log` 
>
>
>   - `Install & Start daemon`       | Запускает АвтоДиверт, записывает Адрес-Домен в `hosts.txt` раз в N секунд
>   - `Uninstall & Stop daemon`      | Отключает АвтоДиверт если тот был ранее запущенен
>   - `Check status`                 | Проверка АвтоДиверта: Запущен ли, номер процесса и т.д.
>   - `Open hosts.txt`               | Открыть сохранённые Адреса-Домены в `hosts.txt`
>   - `Open config in Notepad`       | Открыть Конфиг АвтоДиверта(`autodivert.cfg`) в блокноте, генерируется после первого запуска
>   - `Change interval`              | [Конфиг] настройка раз в N секунд (минимум 10) АвтоДиверт будет сохранять Адреса-Домены
>   - `Change log max lines`         | [Конфиг] настройка размера Лога(`collector.log`)
>   - `clear log now`                | Очистить Лог(`collector.log`)

> [!CAUTION]
> # ВАЖНО
> - Разархивируйте АвтоДиверт
> - АвтоДиверт будет просить права Администратора, это нужно для проверки подключений
> - Меню Автодиверта (`autodivert.bat`) должно находится в одной папке с папкой `AutoDivert` (Иначе меню будет работать некорректно)

[<img src="https://cdn-icons-png.flaticon.com/128/1384/1384060.png" height=50 />](https://discord.gg/kN6R2c6nX9)
[<img src="https://cdn-icons-png.flaticon.com/128/5968/5968756.png" height=50 />](https://www.youtube.com/@redd.flower)
