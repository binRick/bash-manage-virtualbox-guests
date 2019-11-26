if [[ "`command -v VBoxManage`" == "" ]]; then
    echo;echo;
    echo "   [WARNING]  VirtualBox does not seem to installed. Is VBoxManage in the system path?"
    echo;echo;
fi

alias V="command VBoxManage"
