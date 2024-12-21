# Tauthon 2.8 Panda3D Docker Image

This repository contains a Dockerfile to build a Docker image with Tauthon 2.8 and Panda3D. This image is intended for use with older Python 2.7 Panda3D games.

## Features

- Debian-based base image
- Tauthon 2.8 (a fork of Python 2.7 with new features)
- Panda3D game engine (using a [Python 2.7 fork by rocketprogrammer](https://github.com/rocketprogrammer/panda3d/tree/py2))

## Usage

To build the Docker image, run the following command:

```sh
docker build -t tauthon-panda3d .
```

To run a container using the built image:

```sh
docker run -it tauthon-panda3d
```

To make the image more useful, feel free to mount a game source as a directory:

```sh
docker run -v "$(pwd)/toontown:/toontown" -it tauthon-panda3d
```
