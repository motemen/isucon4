from fabric.api import local, put, get, run, task, cd
from fabric.state import env

env.use_ssh_config = True

env.roledefs = {
    'app': [ '203.104.111.191', '203.104.111.192', '203.104.111.193' ]
}

def update():
    with cd("~/deploy"):
        run("git pull")
        run("carton install --deployment")

def restart():
    run("supervisorctl restart isucon_perl")
