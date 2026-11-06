using System.IO;
using System.Windows;
using UopWork.Core;
namespace UopWork.Desktop.Views;
public partial class PasswordWindow : Window
{
    private readonly PasswordStore store;
    private readonly bool change,create;
    public PasswordWindow(PasswordStore store,bool change)
    {
        this.store=store;this.change=change;create=!store.IsConfigured;
        InitializeComponent();
        OldPanel.Visibility=create?Visibility.Collapsed:Visibility.Visible;
        NewPanel.Visibility=create||change?Visibility.Visible:Visibility.Collapsed;
        Heading.Text=create?"Создать пароль управления":change?"Сменить пароль":"Пароль администратора";
        Title=Heading.Text;Accept.Content=create||change?"Сохранить":"Войти";
        Loaded+=(_,_)=>{if(create)NewPassword.Focus();else OldPassword.Focus();};
    }
    private void Submit(object sender,RoutedEventArgs e)
    {
        try
        {
            if(create||change)
            {
                if(NewPassword.Password!=Confirmation.Password)throw new ArgumentException("Новые пароли не совпадают.");
                if(create)store.Initialize(NewPassword.Password);else store.Change(OldPassword.Password,NewPassword.Password);
            }
            else if(!store.Verify(OldPassword.Password))throw new ArgumentException("Неверный пароль.");
            OldPassword.Clear();NewPassword.Clear();Confirmation.Clear();DialogResult=true;
        }
        catch(Exception ex) when(ex is IOException or ArgumentException or InvalidOperationException or System.Text.Json.JsonException)
        {Error.Text=ex.Message;OldPassword.Clear();OldPassword.Focus();}
    }
}
