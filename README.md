# 📝 ZTodo

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Zsh](https://img.shields.io/badge/Zsh-Latest-blue)
![SQLite](https://img.shields.io/badge/SQLite-Latest-blue)

> Powerful SQLite-based task management plugin for Oh-My-Zsh.

---

## 📋 Tabla de contenidos

- [Características](#-características)
- [Instalación](#-instalación)
- [Uso](#-uso)
- [Contribución](#-contribución)
- [Licencia](#-licencia)

## ✨ Características

- 💾 **Persistente**: Storage SQLite
- 🎯 **Prioridades**: Niveles de prioridad
- 📂 **Categorías**: Organización por categorías
- ⏰ **Deadline**: Fechas límite
- 🔍 **Búsqueda**: Búsqueda eficiente

## 🛠️ Instalación

```bash
# Instalar sqlite3 si no lo tienes
sudo apt install sqlite3  # Ubuntu
brew install sqlite       # macOS

# Añadir a .zshrc
plugins=(... ztodo)
```

## 🚀 Uso

```bash
# Añadir tarea
ztodo add "Mi tarea" -p high

# Listar tareas
ztodo list

# Completar tarea
ztodo done <id>
```

## 📝 Contribución

Las contribuciones son bienvenidas. Consulta CONTRIBUTING.md.

## 📄 Licencia

Este proyecto está licenciado bajo los términos de la licencia MIT.

---

*Hecho con ❤️ por [murapadev](https://github.com/murapadev)*
