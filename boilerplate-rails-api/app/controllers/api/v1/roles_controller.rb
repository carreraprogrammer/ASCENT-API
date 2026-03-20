class Api::V1::RolesController < Api::V1::BaseController
  def index
    authorize ::Role, policy_class: Authorization::Policies::RolePolicy
    roles = Authorization::Repositories::RoleRepository.new.all
    render json: Authorization::Presenters::RolePresenter.collection(roles)
  end

  def show
    role = Authorization::Repositories::RoleRepository.new.find(params[:id])
    authorize role, policy_class: Authorization::Policies::RolePolicy
    render json: Authorization::Presenters::RolePresenter.single(role)
  end

  def create
    authorize ::Role, policy_class: Authorization::Policies::RolePolicy
    role = Authorization::Repositories::RoleRepository.new.create(name: params.require(:name), slug: params.require(:slug), description: params[:description])
    render json: Authorization::Presenters::RolePresenter.single(role), status: :created
  end

  def update
    role = Authorization::Repositories::RoleRepository.new.find(params[:id])
    authorize role, policy_class: Authorization::Policies::RolePolicy
    entity = Authorization::Repositories::RoleRepository.new.update(id: params[:id], attrs: params.permit(:name, :slug, :description, :active).to_h.symbolize_keys)
    render json: Authorization::Presenters::RolePresenter.single(entity)
  end

  def destroy
    role = Authorization::Repositories::RoleRepository.new.find(params[:id])
    authorize role, policy_class: Authorization::Policies::RolePolicy
    Authorization::Repositories::RoleRepository.new.destroy(params[:id])
    head :no_content
  end

  def assign_permission
    role = Authorization::Repositories::RoleRepository.new.find(params[:id])
    authorize role, :assign_permission?, policy_class: Authorization::Policies::RolePolicy
    permission = Authorization::Repositories::PermissionRepository.new.find_by_slug(params.require(:permission_slug))
    Authorization::Repositories::RoleRepository.new.assign_permission(role_id: role.id, permission_id: permission.id)
    render json: Authorization::Presenters::RolePresenter.single(Authorization::Repositories::RoleRepository.new.find(role.id))
  end

  def revoke_permission
    role = Authorization::Repositories::RoleRepository.new.find(params[:id])
    authorize role, :revoke_permission?, policy_class: Authorization::Policies::RolePolicy
    permission = Authorization::Repositories::PermissionRepository.new.find_by_slug(params.require(:permission_slug))
    Authorization::Repositories::RoleRepository.new.revoke_permission(role_id: role.id, permission_id: permission.id)
    head :no_content
  end
end
