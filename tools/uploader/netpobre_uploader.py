from __future__ import annotations

import os
import posixpath
import queue
import socket
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from tkinter import (
    BOTH,
    END,
    LEFT,
    RIGHT,
    X,
    Y,
    BooleanVar,
    Button,
    Canvas,
    Checkbutton,
    Entry,
    Frame,
    Label,
    Listbox,
    PhotoImage,
    Radiobutton,
    Scrollbar,
    StringVar,
    Tk,
    Toplevel,
    filedialog,
    messagebox,
)
from tkinter import ttk

import paramiko


APP_VERSION = "1.0.0"
DEFAULT_HOST = "192.168.1.66"
DEFAULT_USER = "netpobre"
LIBRARIES = {
    "Filmes": "/srv/media/filmes",
    "Séries": "/srv/media/series",
    "Vídeos pessoais": "/srv/media/videos-pessoais",
}
VIDEO_EXTENSIONS = {
    ".3gp",
    ".avi",
    ".flv",
    ".m2ts",
    ".m4v",
    ".mkv",
    ".mov",
    ".mp4",
    ".mpeg",
    ".mpg",
    ".mts",
    ".ts",
    ".vob",
    ".webm",
    ".wmv",
}

NAVY = "#061321"
PANEL = "#0D2638"
PANEL_LIGHT = "#123247"
CYAN = "#4CC9F0"
AMBER = "#F7B955"
IVORY = "#F5F1E8"
MUTED = "#9EB0BE"
SUCCESS = "#65D6A6"
ERROR = "#FF786F"


def resource_path(name: str) -> Path:
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[2]))
    if getattr(sys, "_MEIPASS", None):
        return base / name
    return base / "assets" / "branding" / name


def default_key_path() -> Path:
    return Path.home() / ".ssh" / "netpobre_uploader_ed25519"


def format_bytes(value: int) -> str:
    amount = float(value)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if amount < 1024 or unit == "TB":
            return f"{amount:.0f} {unit}" if unit == "B" else f"{amount:.1f} {unit}"
        amount /= 1024
    return f"{amount:.1f} TB"


def safe_subfolder(value: str) -> str:
    normalized = value.strip().replace("\\", "/")
    if not normalized:
        return ""
    path = PurePosixPath(normalized)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise ValueError("Use uma pasta simples, sem '..' ou caminho absoluto.")
    if any(":" in part or "\x00" in part for part in path.parts):
        raise ValueError("O nome da pasta contém um caractere inválido.")
    return path.as_posix()


@dataclass
class UploadItem:
    path: Path
    relative_path: Path
    size: int
    status: str = "Aguardando"
    transferred: int = 0
    row_id: str | None = None
    id: str = field(default_factory=lambda: f"item-{time.time_ns()}")


class NetPobreUploader:
    def __init__(self, root: Tk) -> None:
        self.root = root
        self.root.title(f"NetPobre Enviar {APP_VERSION}")
        self.root.geometry("1040x760")
        self.root.minsize(860, 650)
        self.root.configure(bg=NAVY)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        self.items: list[UploadItem] = []
        self.events: queue.Queue[tuple] = queue.Queue()
        self.cancel_event = threading.Event()
        self.worker: threading.Thread | None = None
        self.uploading = False
        self.total_sent = 0
        self.total_size = 0

        self.library = StringVar(value="Filmes")
        self.subfolder = StringVar()
        self.overwrite = BooleanVar(value=False)
        self.status_text = StringVar(value="Escolha os vídeos que vão entrar no NetPobre.")
        self.queue_summary = StringVar(value="Nenhum vídeo selecionado")
        self.current_file = StringVar(value="Pronto para receber vídeos")

        self._configure_styles()
        self._build_ui()
        self._load_icon()
        self.root.after(100, self._drain_events)

    def _configure_styles(self) -> None:
        style = ttk.Style()
        style.theme_use("clam")
        style.configure(
            "NetPobre.Horizontal.TProgressbar",
            troughcolor=PANEL_LIGHT,
            background=CYAN,
            bordercolor=PANEL_LIGHT,
            lightcolor=CYAN,
            darkcolor=CYAN,
            thickness=12,
        )
        style.configure(
            "Queue.Treeview",
            background=PANEL,
            fieldbackground=PANEL,
            foreground=IVORY,
            rowheight=38,
            borderwidth=0,
            font=("Segoe UI", 10),
        )
        style.configure(
            "Queue.Treeview.Heading",
            background=PANEL,
            foreground=MUTED,
            borderwidth=0,
            font=("Segoe UI Semibold", 9),
        )
        style.map("Queue.Treeview", background=[("selected", PANEL_LIGHT)])

    def _build_ui(self) -> None:
        shell = Frame(self.root, bg=NAVY, padx=34, pady=26)
        shell.pack(fill=BOTH, expand=True)

        header = Frame(shell, bg=NAVY)
        header.pack(fill=X)
        self.logo_canvas = Canvas(
            header, width=64, height=64, bg=NAVY, highlightthickness=0
        )
        self.logo_canvas.pack(side=LEFT, padx=(0, 14))
        brand = Frame(header, bg=NAVY)
        brand.pack(side=LEFT, fill=Y)
        Label(
            brand,
            text="NetPobre Enviar",
            bg=NAVY,
            fg=IVORY,
            font=("Segoe UI Black", 24),
        ).pack(anchor="w")
        Label(
            brand,
            text="Do seu notebook direto para a sala.",
            bg=NAVY,
            fg=MUTED,
            font=("Segoe UI", 11),
        ).pack(anchor="w")

        settings_button = Button(
            header,
            text="Conexão",
            command=self._show_connection,
            bg=NAVY,
            fg=CYAN,
            activebackground=PANEL,
            activeforeground=CYAN,
            relief="flat",
            cursor="hand2",
            font=("Segoe UI Semibold", 10),
            padx=12,
            pady=8,
        )
        settings_button.pack(side=RIGHT, anchor="n")

        stage = Frame(shell, bg=PANEL, padx=26, pady=22)
        stage.pack(fill=X, pady=(24, 16))

        destination_row = Frame(stage, bg=PANEL)
        destination_row.pack(fill=X)
        Label(
            destination_row,
            text="Enviar para",
            bg=PANEL,
            fg=MUTED,
            font=("Segoe UI", 10),
        ).pack(side=LEFT, padx=(0, 16))
        for name in LIBRARIES:
            Radiobutton(
                destination_row,
                text=name,
                variable=self.library,
                value=name,
                indicatoron=False,
                bg=PANEL_LIGHT,
                fg=IVORY,
                selectcolor=CYAN,
                activebackground=CYAN,
                activeforeground=NAVY,
                relief="flat",
                bd=0,
                font=("Segoe UI Semibold", 10),
                padx=16,
                pady=9,
                cursor="hand2",
            ).pack(side=LEFT, padx=(0, 8))

        drop_area = Frame(stage, bg=PANEL, pady=26)
        drop_area.pack(fill=X)
        Label(
            drop_area,
            text="Solte a fita na estante",
            bg=PANEL,
            fg=IVORY,
            font=("Segoe UI Black", 21),
        ).pack()
        Label(
            drop_area,
            text="Selecione arquivos soltos ou uma pasta inteira. Vídeos dentro de subpastas mantêm a organização.",
            bg=PANEL,
            fg=MUTED,
            font=("Segoe UI", 10),
            wraplength=660,
            justify="center",
        ).pack(pady=(5, 18))
        actions = Frame(drop_area, bg=PANEL)
        actions.pack()
        self.select_files_button = self._button(
            actions, "Selecionar vídeos", self._select_files, primary=True
        )
        self.select_files_button.pack(side=LEFT, padx=6)
        self.select_folder_button = self._button(
            actions, "Selecionar uma pasta", self._select_folder
        )
        self.select_folder_button.pack(side=LEFT, padx=6)

        organization = Frame(stage, bg=PANEL)
        organization.pack(fill=X)
        Label(
            organization,
            text="Pasta dentro da biblioteca (opcional)",
            bg=PANEL,
            fg=MUTED,
            font=("Segoe UI", 9),
        ).pack(anchor="w")
        Entry(
            organization,
            textvariable=self.subfolder,
            bg=PANEL_LIGHT,
            fg=IVORY,
            insertbackground=IVORY,
            relief="flat",
            font=("Segoe UI", 11),
            bd=0,
        ).pack(fill=X, ipady=10, pady=(5, 0))
        Label(
            organization,
            text="Exemplo para série: Ted Lasso/Temporada 03",
            bg=PANEL,
            fg=MUTED,
            font=("Segoe UI", 9),
        ).pack(side=LEFT, anchor="w", pady=(5, 0))
        Checkbutton(
            organization,
            text="Substituir arquivo existente",
            variable=self.overwrite,
            bg=PANEL,
            fg=MUTED,
            activebackground=PANEL,
            activeforeground=IVORY,
            selectcolor=PANEL_LIGHT,
            font=("Segoe UI", 9),
            cursor="hand2",
        ).pack(side=RIGHT, anchor="e", pady=(5, 0))

        queue_header = Frame(shell, bg=NAVY)
        queue_header.pack(fill=X, pady=(4, 8))
        Label(
            queue_header,
            text="Fila de envio",
            bg=NAVY,
            fg=IVORY,
            font=("Segoe UI Bold", 14),
        ).pack(side=LEFT)
        Label(
            queue_header,
            textvariable=self.queue_summary,
            bg=NAVY,
            fg=MUTED,
            font=("Segoe UI", 10),
        ).pack(side=RIGHT)
        self.remove_button = Button(
            queue_header,
            text="Remover selecionados",
            command=self._remove_selected,
            bg=NAVY,
            fg=CYAN,
            activebackground=PANEL,
            activeforeground=CYAN,
            relief="flat",
            bd=0,
            cursor="hand2",
            font=("Segoe UI Semibold", 9),
            padx=10,
        )
        self.remove_button.pack(side=RIGHT, padx=(0, 14))

        queue_frame = Frame(shell, bg=PANEL)
        queue_frame.pack(fill=BOTH, expand=True)
        columns = ("name", "size", "status")
        self.tree = ttk.Treeview(
            queue_frame,
            columns=columns,
            show="headings",
            style="Queue.Treeview",
            selectmode="extended",
        )
        self.tree.heading("name", text="Vídeo")
        self.tree.heading("size", text="Tamanho")
        self.tree.heading("status", text="Situação")
        self.tree.column("name", minwidth=320, width=560, anchor="w")
        self.tree.column("size", minwidth=90, width=110, anchor="e")
        self.tree.column("status", minwidth=150, width=190, anchor="w")
        scrollbar = Scrollbar(queue_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        self.tree.pack(side=LEFT, fill=BOTH, expand=True)
        scrollbar.pack(side=RIGHT, fill=Y)

        footer = Frame(shell, bg=NAVY)
        footer.pack(fill=X, pady=(16, 0))
        progress_side = Frame(footer, bg=NAVY)
        progress_side.pack(side=LEFT, fill=X, expand=True, padx=(0, 20))
        Label(
            progress_side,
            textvariable=self.current_file,
            bg=NAVY,
            fg=IVORY,
            font=("Segoe UI Semibold", 10),
            anchor="w",
        ).pack(fill=X)
        self.progress = ttk.Progressbar(
            progress_side,
            maximum=100,
            value=0,
            style="NetPobre.Horizontal.TProgressbar",
        )
        self.progress.pack(fill=X, pady=(7, 5))
        Label(
            progress_side,
            textvariable=self.status_text,
            bg=NAVY,
            fg=MUTED,
            font=("Segoe UI", 9),
            anchor="w",
        ).pack(fill=X)

        self.clear_button = self._button(footer, "Limpar", self._clear_queue)
        self.clear_button.pack(side=LEFT, padx=(0, 8), anchor="s")
        self.send_button = self._button(
            footer, "Enviar agora", self._start_upload, primary=True
        )
        self.send_button.pack(side=LEFT, anchor="s")

    def _button(self, parent: Frame, text: str, command, primary: bool = False) -> Button:
        background = AMBER if primary else PANEL_LIGHT
        foreground = NAVY if primary else IVORY
        return Button(
            parent,
            text=text,
            command=command,
            bg=background,
            fg=foreground,
            activebackground=CYAN if primary else PANEL,
            activeforeground=NAVY if primary else IVORY,
            relief="flat",
            bd=0,
            font=("Segoe UI Bold", 10),
            padx=18,
            pady=11,
            cursor="hand2",
        )

    def _load_icon(self) -> None:
        try:
            self.logo_image = PhotoImage(file=str(resource_path("netpobre-mascot-transparent.png")))
            width = self.logo_image.width()
            factor = max(1, width // 58)
            self.logo_image = self.logo_image.subsample(factor, factor)
            self.logo_canvas.create_image(32, 32, image=self.logo_image)
            icon_path = resource_path("netpobre-icon.ico")
            if icon_path.exists():
                self.root.iconbitmap(str(icon_path))
        except Exception:
            self.logo_canvas.create_text(32, 32, text="📺", fill=IVORY, font=("Segoe UI Emoji", 28))

    def _select_files(self) -> None:
        paths = filedialog.askopenfilenames(
            title="Escolha os vídeos",
            filetypes=[
                ("Arquivos de vídeo", " ".join(f"*{ext}" for ext in sorted(VIDEO_EXTENSIONS))),
                ("Todos os arquivos", "*.*"),
            ],
        )
        self._add_paths([(Path(path), Path(path).name) for path in paths])

    def _select_folder(self) -> None:
        selected = filedialog.askdirectory(title="Escolha a pasta com os vídeos")
        if not selected:
            return
        root = Path(selected)
        paths = [
            (path, path.relative_to(root))
            for path in root.rglob("*")
            if path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS
        ]
        if not paths:
            messagebox.showinfo(
                "Nenhum vídeo encontrado",
                "A pasta escolhida não contém arquivos de vídeo reconhecidos.",
            )
            return
        self._add_paths(paths)

    def _add_paths(self, paths: list[tuple[Path, Path | str]]) -> None:
        existing = {item.path.resolve() for item in self.items}
        added = 0
        for raw_path, relative in paths:
            path = raw_path.resolve()
            if not path.is_file() or path in existing:
                continue
            if path.suffix.lower() not in VIDEO_EXTENSIONS:
                continue
            item = UploadItem(
                path=path,
                relative_path=Path(relative),
                size=path.stat().st_size,
            )
            item.row_id = self.tree.insert(
                "",
                END,
                values=(str(item.relative_path), format_bytes(item.size), item.status),
            )
            self.items.append(item)
            existing.add(path)
            added += 1
        self._update_summary()
        if added:
            self.status_text.set(f"{added} vídeo(s) adicionado(s). Revise e envie quando quiser.")

    def _update_summary(self) -> None:
        total = sum(item.size for item in self.items)
        count = len(self.items)
        if count == 0:
            self.queue_summary.set("Nenhum vídeo selecionado")
        else:
            self.queue_summary.set(f"{count} vídeo(s) · {format_bytes(total)}")

    def _clear_queue(self) -> None:
        if self.uploading:
            if messagebox.askyesno(
                "Parar o envio?",
                "O arquivo atual ficará guardado parcialmente e poderá continuar em uma nova tentativa.",
            ):
                self.cancel_event.set()
                self.status_text.set("Parando com segurança…")
            return
        self.items.clear()
        for row in self.tree.get_children():
            self.tree.delete(row)
        self.progress["value"] = 0
        self.current_file.set("Pronto para receber vídeos")
        self.status_text.set("Escolha os vídeos que vão entrar no NetPobre.")
        self._update_summary()

    def _remove_selected(self) -> None:
        if self.uploading:
            return
        selected = set(self.tree.selection())
        if not selected:
            return
        self.items = [item for item in self.items if item.row_id not in selected]
        for row in selected:
            self.tree.delete(row)
        self._update_summary()
        self.status_text.set("Itens selecionados removidos da fila.")

    def _start_upload(self) -> None:
        if self.uploading:
            return
        if not self.items:
            messagebox.showinfo("Fila vazia", "Selecione pelo menos um vídeo para enviar.")
            return
        try:
            subfolder = safe_subfolder(self.subfolder.get())
        except ValueError as error:
            messagebox.showerror("Pasta inválida", str(error))
            return
        key_path = default_key_path()
        if not key_path.exists():
            messagebox.showerror(
                "Chave não encontrada",
                f"A chave deste notebook não foi encontrada em:\n{key_path}",
            )
            return

        self.uploading = True
        self.cancel_event.clear()
        self.total_sent = 0
        self.total_size = sum(item.size for item in self.items if item.status != "Enviado")
        for item in self.items:
            if item.status != "Enviado":
                item.status = "Aguardando"
                item.transferred = 0
                self._update_row(item)
        self._set_controls(False)
        self.send_button.configure(text="Enviando…")
        self.status_text.set("Conectando ao servidor NetPobre…")
        self.worker = threading.Thread(
            target=self._upload_worker,
            args=(self.library.get(), subfolder, self.overwrite.get()),
            daemon=True,
        )
        self.worker.start()

    def _connect(self) -> tuple[paramiko.SSHClient, paramiko.SFTPClient]:
        client = paramiko.SSHClient()
        client.load_system_host_keys()
        client.set_missing_host_key_policy(paramiko.RejectPolicy())
        client.connect(
            DEFAULT_HOST,
            username=DEFAULT_USER,
            key_filename=str(default_key_path()),
            timeout=10,
            banner_timeout=10,
            auth_timeout=10,
            look_for_keys=False,
            allow_agent=False,
        )
        transport = client.get_transport()
        if transport:
            transport.set_keepalive(30)
        return client, client.open_sftp()

    def _upload_worker(self, library: str, subfolder: str, overwrite: bool) -> None:
        base = LIBRARIES[library]
        client: paramiko.SSHClient | None = None
        sftp: paramiko.SFTPClient | None = None
        completed = 0
        failures = 0
        try:
            client, sftp = self._connect()
            self._ensure_remote_dir(sftp, base)
            stat = sftp.statvfs(base)
            free_bytes = stat.f_bavail * stat.f_frsize
            needed = sum(item.size for item in self.items if item.status != "Enviado")
            if free_bytes < needed + 250 * 1024 * 1024:
                raise RuntimeError(
                    f"O servidor tem {format_bytes(free_bytes)} livres, mas o envio precisa de {format_bytes(needed)}."
                )

            for item in self.items:
                if item.status == "Enviado":
                    continue
                if self.cancel_event.is_set():
                    break
                attempts = 0
                while attempts < 3 and not self.cancel_event.is_set():
                    attempts += 1
                    try:
                        if sftp is None:
                            client, sftp = self._connect()
                        self._send_item(sftp, item, base, subfolder, overwrite)
                        completed += 1
                        break
                    except FileExistsError:
                        item.status = "Já existe"
                        self.events.put(("row", item.id, item.status, item.transferred))
                        completed += 1
                        break
                    except Exception as error:
                        if attempts >= 3:
                            item.status = "Falhou"
                            self.events.put(("row", item.id, item.status, item.transferred))
                            self.events.put(("error", item.path.name, str(error)))
                            failures += 1
                            break
                        item.status = f"Reconectando ({attempts}/3)"
                        self.events.put(("row", item.id, item.status, item.transferred))
                        try:
                            if sftp:
                                sftp.close()
                            if client:
                                client.close()
                        except Exception:
                            pass
                        client = None
                        sftp = None
                        time.sleep(2)

            if self.cancel_event.is_set():
                self.events.put(("finished", "cancelled", completed, failures))
            else:
                self.events.put(("finished", "done", completed, failures))
        except (paramiko.SSHException, socket.error) as error:
            self.events.put(("fatal", f"Não foi possível conectar ao servidor: {error}"))
        except Exception as error:
            self.events.put(("fatal", str(error)))
        finally:
            try:
                if sftp:
                    sftp.close()
                if client:
                    client.close()
            except Exception:
                pass

    def _send_item(
        self,
        sftp: paramiko.SFTPClient,
        item: UploadItem,
        base: str,
        subfolder: str,
        overwrite: bool,
    ) -> None:
        relative = PurePosixPath(*item.relative_path.parts).as_posix()
        remote_dir = posixpath.join(base, subfolder, posixpath.dirname(relative))
        self._ensure_remote_dir(sftp, remote_dir)
        remote_path = posixpath.join(remote_dir, posixpath.basename(relative))
        partial_path = f"{remote_path}.netpobre-upload.part"

        try:
            sftp.stat(remote_path)
            if not overwrite:
                raise FileExistsError(remote_path)
            sftp.remove(remote_path)
        except FileNotFoundError:
            pass

        offset = 0
        try:
            offset = sftp.stat(partial_path).st_size
            if offset > item.size:
                sftp.remove(partial_path)
                offset = 0
        except FileNotFoundError:
            pass

        item.transferred = offset
        item.status = "Enviando"
        self.events.put(("current", item.path.name))
        self.events.put(("row", item.id, item.status, item.transferred))

        with item.path.open("rb") as source:
            source.seek(offset)
            mode = "ab" if offset else "wb"
            with sftp.file(partial_path, mode) as target:
                target.set_pipelined(True)
                while not self.cancel_event.is_set():
                    chunk = source.read(1024 * 1024)
                    if not chunk:
                        break
                    target.write(chunk)
                    item.transferred += len(chunk)
                    self.events.put(("progress", item.id, item.transferred, item.size))
                target.flush()

        if self.cancel_event.is_set():
            item.status = "Pausado"
            self.events.put(("row", item.id, item.status, item.transferred))
            return

        remote_size = sftp.stat(partial_path).st_size
        if remote_size != item.size:
            raise IOError(
                f"O servidor recebeu {format_bytes(remote_size)} de {format_bytes(item.size)}."
            )
        sftp.rename(partial_path, remote_path)
        sftp.chmod(remote_path, 0o664)
        item.status = "Enviado"
        self.events.put(("row", item.id, item.status, item.size))

    @staticmethod
    def _ensure_remote_dir(sftp: paramiko.SFTPClient, remote_dir: str) -> None:
        current = "/"
        for part in PurePosixPath(remote_dir).parts:
            if part == "/":
                continue
            current = posixpath.join(current, part)
            try:
                sftp.stat(current)
            except FileNotFoundError:
                sftp.mkdir(current, mode=0o2775)

    def _drain_events(self) -> None:
        try:
            while True:
                event = self.events.get_nowait()
                kind = event[0]
                if kind == "current":
                    self.current_file.set(f"Enviando {event[1]}")
                elif kind == "row":
                    item = self._item_by_id(event[1])
                    if item:
                        item.status = event[2]
                        item.transferred = event[3]
                        self._update_row(item)
                elif kind == "progress":
                    item = self._item_by_id(event[1])
                    if item:
                        previous = item.transferred
                        item.transferred = event[2]
                        self.total_sent += max(0, item.transferred - previous)
                        percent = (item.transferred / event[3]) * 100 if event[3] else 0
                        item.status = f"Enviando · {percent:.0f}%"
                        self._update_row(item)
                        overall = (
                            sum(min(queued.transferred, queued.size) for queued in self.items)
                            / sum(queued.size for queued in self.items)
                            * 100
                        )
                        self.progress["value"] = overall
                        self.status_text.set(
                            f"{overall:.0f}% concluído · pode deixar esta janela aberta em segundo plano."
                        )
                elif kind == "error":
                    self.status_text.set(f"Falha em {event[1]}: {event[2]}")
                elif kind == "fatal":
                    self._finish_ui()
                    messagebox.showerror("Envio interrompido", event[1])
                elif kind == "finished":
                    self._finish_ui()
                    if event[1] == "cancelled":
                        self.current_file.set("Envio pausado")
                        self.status_text.set(
                            "A parte já enviada foi preservada. Clique em Enviar agora para continuar."
                        )
                    elif event[3]:
                        self.current_file.set("Envio concluído com pendências")
                        self.status_text.set(
                            f"{event[2]} concluído(s) e {event[3]} com falha. Tente novamente para continuar."
                        )
                    else:
                        self.progress["value"] = 100
                        self.current_file.set("Tudo chegou ao NetPobre")
                        self.status_text.set(
                            f"{event[2]} vídeo(s) enviado(s). O Jellyfin vai adicioná-los automaticamente."
                        )
                        messagebox.showinfo(
                            "Envio concluído",
                            f"{event[2]} vídeo(s) chegaram ao servidor.\n\nEles aparecerão no NetPobre após a leitura automática da biblioteca.",
                        )
        except queue.Empty:
            pass
        self.root.after(100, self._drain_events)

    def _update_row(self, item: UploadItem) -> None:
        if item.row_id:
            self.tree.item(
                item.row_id,
                values=(str(item.relative_path), format_bytes(item.size), item.status),
            )

    def _item_by_id(self, item_id: str) -> UploadItem | None:
        return next((item for item in self.items if item.id == item_id), None)

    def _set_controls(self, enabled: bool) -> None:
        state = "normal" if enabled else "disabled"
        self.select_files_button.configure(state=state)
        self.select_folder_button.configure(state=state)
        self.send_button.configure(state=state)
        self.remove_button.configure(state=state)
        self.clear_button.configure(text="Limpar" if enabled else "Parar", state="normal")

    def _finish_ui(self) -> None:
        self.uploading = False
        self._set_controls(True)
        self.send_button.configure(text="Enviar agora")

    def _show_connection(self) -> None:
        window = Toplevel(self.root)
        window.title("Conexão com o servidor")
        window.geometry("460x250")
        window.resizable(False, False)
        window.configure(bg=NAVY)
        body = Frame(window, bg=NAVY, padx=28, pady=24)
        body.pack(fill=BOTH, expand=True)
        Label(
            body,
            text="Servidor de casa",
            bg=NAVY,
            fg=IVORY,
            font=("Segoe UI Bold", 17),
        ).pack(anchor="w")
        Label(
            body,
            text=f"{DEFAULT_USER}@{DEFAULT_HOST}",
            bg=NAVY,
            fg=CYAN,
            font=("Segoe UI Semibold", 12),
        ).pack(anchor="w", pady=(8, 18))
        Label(
            body,
            text="Este notebook usa uma chave própria. Nenhuma senha fica salva no aplicativo.",
            bg=NAVY,
            fg=MUTED,
            font=("Segoe UI", 10),
            wraplength=390,
            justify="left",
        ).pack(anchor="w")
        self._button(body, "Testar conexão", lambda: self._test_connection(window), True).pack(
            anchor="w", pady=(22, 0)
        )

    def _test_connection(self, parent: Toplevel) -> None:
        try:
            client, sftp = self._connect()
            stat = sftp.statvfs("/srv/media")
            free = stat.f_bavail * stat.f_frsize
            sftp.close()
            client.close()
            messagebox.showinfo(
                "Servidor conectado",
                f"Conexão pronta. Espaço livre: {format_bytes(free)}.",
                parent=parent,
            )
        except Exception as error:
            messagebox.showerror(
                "Servidor indisponível",
                f"Confira se este notebook está na rede de casa.\n\n{error}",
                parent=parent,
            )

    def _on_close(self) -> None:
        if self.uploading:
            if not messagebox.askyesno(
                "Fechar durante o envio?",
                "O arquivo atual ficará parcial no servidor e continuará na próxima tentativa.",
            ):
                return
            self.cancel_event.set()
        self.root.destroy()


def main() -> None:
    root = Tk()
    NetPobreUploader(root)
    root.mainloop()


if __name__ == "__main__":
    main()
